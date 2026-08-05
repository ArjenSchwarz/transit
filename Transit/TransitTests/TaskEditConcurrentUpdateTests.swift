import Foundation
import SwiftData
import Testing
@testable import Transit

// MARK: - Shared fixture

/// Services wired to one context, the way the app wires the UI and the MCP
/// server: both write to the same `TransitTask` instance.
@MainActor
struct TaskEditTestEnv {
    let context: ModelContext
    let taskService: TaskService
    let milestoneService: MilestoneService
    let applier: TaskEditApplier
    let project: Project

    static func make() throws -> TaskEditTestEnv {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
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
        return TaskEditTestEnv(
            context: context,
            taskService: taskService,
            milestoneService: milestoneService,
            applier: TaskEditApplier(taskService: taskService, milestoneService: milestoneService),
            project: project
        )
    }

    func makeTask(
        name: String = "Original name",
        description: String? = "Original description"
    ) async throws -> TransitTask {
        try await taskService.createTask(
            name: name,
            description: description,
            type: .feature,
            project: project
        )
    }

    /// Runs the save the editor would run for `merge`.
    func apply(
        _ merge: TaskEditMerge,
        edited: TaskEditSnapshot,
        to task: TransitTask,
        project: Project? = nil,
        milestone: Milestone? = nil
    ) throws {
        try applier.apply(
            merge,
            edited: edited,
            to: task,
            project: project,
            milestone: milestone
        )
    }
}

// MARK: - Concurrent update regression

/// Regression tests for T-1798.
///
/// `TaskEditView` snapshotted every editable field into `@State` on appear and
/// wrote all of them back on save, so any change an external writer (MCP over
/// the shared `mainContext`, or a CloudKit merge) made to the live task while
/// the editor was open was silently reverted by the next save.
///
/// The fix is a three-way comparison — load-time baseline vs. form values vs.
/// live task — that submits only user-changed fields.
@MainActor @Suite(.serialized)
struct TaskEditConcurrentUpdateTests {

    /// The exact scenario from T-1798: open the editor, let MCP update the task,
    /// change only priority in the form, save. The MCP change must survive.
    @Test func externalUpdateSurvivesUnrelatedFormEdit() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()

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

        try env.apply(merge, edited: edited, to: task)

        #expect(task.priority == .high)
        #expect(task.name == "Renamed by MCP")
        #expect(task.taskDescription == "Rewritten by MCP")
        #expect(task.type == .bug)
        #expect(task.metadata == ["source": "mcp"])
    }

    /// A save with no form edits at all must not write anything, so an external
    /// change survives the user merely opening and closing the editor.
    @Test func untouchedFormWritesNothing() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, name: "Renamed by MCP", type: .chore)

        let merge = TaskEditMerge(original: baseline, edited: baseline, live: TaskEditSnapshot(task: task))
        #expect(merge.hasChanges == false)
        #expect(merge.hasConflicts == false)

        try env.apply(merge, edited: baseline, to: task)

        #expect(task.name == "Renamed by MCP")
        #expect(task.type == .chore)
    }

    /// An external status change must survive an unrelated form edit, including
    /// the `lastStatusChangeDate` side effect StatusEngine applied for it.
    @Test func externalStatusChangeSurvivesNameEdit() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateStatus(task: task, to: .inProgress)
        let externalStatusDate = task.lastStatusChangeDate

        var edited = baseline
        edited.name = "Renamed by the user"

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(merge.changedFields == [.name])

        try env.apply(merge, edited: edited, to: task)

        #expect(task.name == "Renamed by the user")
        #expect(task.status == .inProgress)
        #expect(task.lastStatusChangeDate == externalStatusDate)
    }

    /// An external milestone assignment must survive a priority-only form edit,
    /// even though the form still shows the "no milestone" it loaded.
    @Test func externalMilestoneAssignmentSurvivesPriorityEdit() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
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

        try env.apply(merge, edited: edited, to: task, milestone: nil)

        #expect(task.priority == .low)
        #expect(task.milestone?.id == milestone.id)
    }

    /// Loading and immediately saving must not look like an edit just because
    /// the stored value carries whitespace the form would have trimmed.
    @Test func untrimmedStoredValuesDoNotLookLikeEdits() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
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
        #expect(merge.hasChanges == false)
    }
}

// MARK: - Conflict detection

/// Covers the case the merge cannot resolve on its own: the user and an external
/// writer changed the *same* field. The merge reports it so the editor can ask
/// rather than silently picking a winner.
@MainActor @Suite(.serialized)
struct TaskEditConflictDetectionTests {

    /// Different values on the same field is a conflict.
    @Test func sameFieldChangedByBothSidesIsAConflict() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
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
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, name: "Agreed name")

        var edited = baseline
        edited.name = "Agreed name"

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(merge.changedFields == [.name])
        #expect(merge.hasConflicts == false)
    }

    /// Conflicts are per field: a clean edit alongside a conflicting one is still
    /// listed as changed, and a purely external change is neither.
    @Test func conflictsAreDetectedPerFieldNotForTheWholeForm() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, name: "Renamed by MCP", type: .chore)

        var edited = baseline
        edited.name = "Renamed by the user"
        edited.priority = .high

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(merge.changedFields == [.name, .priority])
        #expect(merge.conflictingFields == [.name])
        #expect(merge.changed(.type) == false)
    }

    /// Conflicting field labels are human readable and listed in a stable order.
    @Test func conflictingFieldNamesUseStableDisplayLabels() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
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

    /// "Use Updated Values" rebuilds the whole draft from the latest task,
    /// preserving only genuine non-conflicting user edits. Untouched external
    /// changes must not remain stale and become accidental edits after rebase.
    @Test func adoptingLiveValuesRefreshesUntouchedFieldsAndKeepsCleanEdits() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, name: "Renamed by MCP", type: .bug)
        try env.taskService.updateStatus(task: task, to: .done)

        var edited = baseline
        edited.name = "Renamed by the user"
        edited.priority = .high

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        let rebased = merge.rebasedEdited

        #expect(rebased.name == "Renamed by MCP")
        #expect(rebased.type == .bug)
        #expect(rebased.status == .done)
        #expect(rebased.priority == .high)

        let afterRebase = TaskEditMerge(original: merge.live, edited: rebased, live: merge.live)
        #expect(afterRebase.changedFields == [.priority])
        #expect(afterRebase.hasConflicts == false)
    }

    /// Keep-mine consent applies only to the exact conflict values shown. If an
    /// external writer changes a shown value and introduces another conflict
    /// while the alert is open, the current merge must require a new alert.
    @Test func changedConflictSnapshotInvalidatesAlertConsent() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        var edited = baseline
        edited.name = "Renamed by the user"
        edited.status = .planning

        try env.taskService.updateTask(task, name: "First MCP name")
        let shown = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(shown.conflictingFields == [.name])

        try env.taskService.updateTask(task, name: "Second MCP name")
        let changedValue = TaskEditMerge(
            original: baseline,
            edited: edited,
            live: TaskEditSnapshot(task: task)
        )
        #expect(changedValue.conflictingFields == [.name])
        #expect(changedValue.hasSameConflictSnapshot(as: shown) == false)

        try env.taskService.updateStatus(task: task, to: .done)
        let current = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(current.conflictingFields == [.name, .status])
        #expect(current.hasSameConflictSnapshot(as: shown) == false)
    }

    /// Metadata is compared by value, so an external metadata write conflicts
    /// with a user metadata edit rather than being silently overwritten.
    @Test func metadataConflictIsDetected() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, metadata: ["branch": "mcp"])

        var edited = baseline
        edited.metadata = ["branch": "user"]

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(merge.conflictingFields == [.metadata])
    }

    /// The alert names the fields and both choices, so the user is not asked a
    /// blind question.
    @Test func conflictDescriptionNamesFieldsAndChoices() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        try env.taskService.updateTask(task, name: "MCP name")

        var edited = baseline
        edited.name = "User name"

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        let message = merge.conflictDescription

        #expect(message.contains("Name"))
        #expect(message.contains("Keep My Changes"))
        #expect(message.contains("Use Updated Values"))
    }
}
