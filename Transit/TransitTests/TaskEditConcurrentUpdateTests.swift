import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1798.
///
/// `TaskEditView` snapshotted every editable field into `@State` on appear and
/// wrote all of them back on save, so any change an external writer (MCP over
/// the shared `mainContext`, or a CloudKit merge) made to the live task while
/// the editor was open was silently reverted by the next save.
///
/// The fix is a three-way comparison — load-time baseline vs. form values vs.
/// live task — that submits only user-changed fields and reports fields both
/// sides changed as conflicts.
@MainActor @Suite(.serialized)
struct TaskEditConcurrentUpdateTests {

    // MARK: - Helpers

    private struct TestEnv {
        let context: ModelContext
        let taskService: TaskService
        let milestoneService: MilestoneService
        let applier: TaskEditApplier
        let project: Project
    }

    private func makeEnv() throws -> TestEnv {
        let context = try TestModelContainer.newContext()
        let taskService = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore())
        )
        let milestoneService = MilestoneService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore())
        )
        let project = Project(name: "Transit", description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return TestEnv(
            context: context,
            taskService: taskService,
            milestoneService: milestoneService,
            applier: TaskEditApplier(taskService: taskService, milestoneService: milestoneService),
            project: project
        )
    }

    private func makeTask(
        in env: TestEnv,
        name: String = "Original name",
        description: String? = "Original description"
    ) async throws -> TransitTask {
        try await env.taskService.createTask(
            name: name,
            description: description,
            type: .feature,
            project: env.project
        )
    }

    // MARK: - Headline regression (ticket repro)

    /// The exact scenario from T-1798: open the editor, let MCP update the task,
    /// change only priority in the form, save. The MCP change must survive.
    @Test func externalUpdateSurvivesUnrelatedFormEdit() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)

        // Editor appears and captures its baseline.
        let baseline = TaskEditSnapshot(task: task)

        // MCP writes to the same live task while the editor is open.
        try env.taskService.updateTask(
            task,
            name: "Renamed by MCP",
            description: "Rewritten by MCP",
            type: .bug,
            metadata: ["source": "mcp"]
        )

        // The user touches only the priority picker.
        var edited = baseline
        edited.priority = .high

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(merge.changedFields == [.priority])
        #expect(merge.hasConflicts == false)

        try env.applier.apply(merge, edited: edited, to: task, project: env.project, milestone: nil)

        #expect(task.priority == .high)
        #expect(task.name == "Renamed by MCP")
        #expect(task.taskDescription == "Rewritten by MCP")
        #expect(task.type == .bug)
        #expect(task.metadata == ["source": "mcp"])
    }

    /// A save with no form edits at all must not write anything, so an external
    /// change is untouched even when the user just opens and closes the editor.
    @Test func untouchedFormWritesNothing() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, name: "Renamed by MCP", type: .chore)

        let merge = TaskEditMerge(original: baseline, edited: baseline, live: TaskEditSnapshot(task: task))
        #expect(merge.changedFields.isEmpty)
        #expect(merge.hasConflicts == false)

        try env.applier.apply(merge, edited: baseline, to: task, project: env.project, milestone: nil)

        #expect(task.name == "Renamed by MCP")
        #expect(task.type == .chore)
    }

    /// An external status change must survive an unrelated form edit, including
    /// the `lastStatusChangeDate` side effect StatusEngine applied for it.
    @Test func externalStatusChangeSurvivesNameEdit() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateStatus(task: task, to: .inProgress)
        let externalStatusDate = task.lastStatusChangeDate

        var edited = baseline
        edited.name = "Renamed by the user"

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(merge.changedFields == [.name])

        try env.applier.apply(merge, edited: edited, to: task, project: env.project, milestone: nil)

        #expect(task.name == "Renamed by the user")
        #expect(task.status == .inProgress)
        #expect(task.lastStatusChangeDate == externalStatusDate)
    }

    /// An external milestone assignment must survive a priority-only form edit.
    @Test func externalMilestoneAssignmentSurvivesPriorityEdit() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        let baseline = TaskEditSnapshot(task: task)

        let milestone = try await env.milestoneService.createMilestone(
            name: "Launch",
            description: nil,
            project: env.project
        )
        try env.milestoneService.setMilestone(milestone, on: task)

        var edited = baseline
        edited.priority = .low

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(merge.changedFields == [.priority])

        // The form still shows "no milestone" because that is what it loaded.
        try env.applier.apply(merge, edited: edited, to: task, project: env.project, milestone: nil)

        #expect(task.priority == .low)
        #expect(task.milestone?.id == milestone.id)
    }

    // MARK: - Conflict detection

    /// When the user and an external writer change the same field to different
    /// values, the merge reports a conflict instead of picking a winner.
    @Test func sameFieldChangedByBothSidesIsAConflict() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, name: "Renamed by MCP")

        var edited = baseline
        edited.name = "Renamed by the user"

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(merge.hasConflicts)
        #expect(merge.conflictingFields == [.name])
        #expect(merge.conflictingFieldNames == ["Name"])
    }

    /// Both sides landing on the same value is agreement, not a conflict.
    @Test func sameFieldChangedToSameValueIsNotAConflict() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, name: "Agreed name")

        var edited = baseline
        edited.name = "Agreed name"

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(merge.changedFields == [.name])
        #expect(merge.hasConflicts == false)
    }

    /// Conflicts are reported per field: a clean edit alongside a conflicting one
    /// is still listed as changed so it can be written once the user decides.
    @Test func conflictsAreDetectedPerFieldNotForTheWholeForm() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, name: "Renamed by MCP", type: .chore)

        var edited = baseline
        edited.name = "Renamed by the user"
        edited.priority = .high

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(merge.changedFields == [.name, .priority])
        #expect(merge.conflictingFields == [.name])
        // Type was changed only externally, so it is neither written nor flagged.
        #expect(merge.changed(.type) == false)
    }

    /// Conflicting field labels are human readable and listed in a stable order.
    @Test func conflictingFieldNamesUseStableDisplayLabels() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, name: "MCP name", type: .bug)
        try env.taskService.updateStatus(task: task, to: .done)

        var edited = baseline
        edited.status = .planning
        edited.name = "User name"
        edited.type = .chore

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(merge.conflictingFieldNames == ["Name", "Type", "Status"])
    }

    /// Metadata is compared by value, so an external metadata write conflicts
    /// with a user metadata edit rather than being silently overwritten.
    @Test func metadataConflictIsDetected() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, metadata: ["branch": "mcp"])

        var edited = baseline
        edited.metadata = ["branch": "user"]

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(merge.conflictingFields == [.metadata])
    }

    // MARK: - Normal editing still works

    /// With no external writer involved, every user edit is applied as before.
    @Test func userEditsApplyWhenNothingElseChanged() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        let baseline = TaskEditSnapshot(task: task)

        let milestone = try await env.milestoneService.createMilestone(
            name: "Launch",
            description: nil,
            project: env.project
        )

        var edited = baseline
        edited.name = "New name"
        edited.description = "New description"
        edited.type = .research
        edited.priority = .high
        edited.status = .inProgress
        edited.metadata = ["key": "value"]
        edited.milestoneID = milestone.id

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(merge.hasConflicts == false)

        try env.applier.apply(merge, edited: edited, to: task, project: env.project, milestone: milestone)

        #expect(task.name == "New name")
        #expect(task.taskDescription == "New description")
        #expect(task.type == .research)
        #expect(task.priority == .high)
        #expect(task.status == .inProgress)
        #expect(task.metadata == ["key": "value"])
        #expect(task.milestone?.id == milestone.id)
    }

    /// T-854: emptying the description field must still clear a stored
    /// description rather than being read as "no change requested".
    @Test func emptyingDescriptionStillClearsIt() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        let baseline = TaskEditSnapshot(task: task)

        var edited = baseline
        edited.description = ""

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(merge.changedFields == [.description])

        try env.applier.apply(merge, edited: edited, to: task, project: env.project, milestone: nil)

        #expect(task.taskDescription == nil)
    }

    /// A user-initiated project move still clears the milestone (Decision 6).
    @Test func changingProjectClearsMilestone() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        let milestone = try await env.milestoneService.createMilestone(
            name: "Launch",
            description: nil,
            project: env.project
        )
        try env.milestoneService.setMilestone(milestone, on: task)

        let otherProject = Project(name: "Other", description: "", gitRepo: nil, colorHex: "#00FF00")
        env.context.insert(otherProject)

        let baseline = TaskEditSnapshot(task: task)
        var edited = baseline
        edited.projectID = otherProject.id
        edited.milestoneID = nil

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(merge.changedFields == [.project, .milestone])

        try env.applier.apply(merge, edited: edited, to: task, project: otherProject, milestone: nil)

        #expect(task.project?.id == otherProject.id)
        #expect(task.milestone == nil)
    }

    /// Loading and immediately saving must not be seen as an edit just because
    /// the stored values carry whitespace the form would trim.
    @Test func untrimmedStoredValuesDoNotLookLikeEdits() async throws {
        let env = try makeEnv()
        let task = try await makeTask(in: env)
        task.taskDescription = "  Original description\n"

        let baseline = TaskEditSnapshot(task: task)
        let edited = TaskEditSnapshot(
            name: task.name,
            description: task.taskDescription ?? "",
            type: task.type,
            priority: task.priority,
            status: task.status,
            projectID: task.project?.id,
            milestoneID: task.milestone?.id,
            metadata: task.metadata
        )

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(merge.changedFields.isEmpty)
    }
}
