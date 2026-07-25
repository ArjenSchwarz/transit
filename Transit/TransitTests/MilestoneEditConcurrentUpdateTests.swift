import Foundation
import SwiftData
import Testing
@testable import Transit

// MARK: - Shared fixture

/// A `MilestoneService` wired to one context, the way the app wires the UI and
/// the MCP server: both write to the same `Milestone` instance.
@MainActor
struct MilestoneEditTestEnv {
    let context: ModelContext
    let milestoneService: MilestoneService
    let applier: MilestoneEditApplier
    let project: Project

    static func make() throws -> MilestoneEditTestEnv {
        let context = try TestModelContainer.newContext()
        let milestoneService = MilestoneService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore())
        )
        let project = Project(name: "Transit", description: "", gitRepo: nil, colorHex: "FF0000")
        context.insert(project)
        return MilestoneEditTestEnv(
            context: context,
            milestoneService: milestoneService,
            applier: MilestoneEditApplier(milestoneService: milestoneService),
            project: project
        )
    }

    func makeMilestone(
        name: String = "Launch",
        description: String? = "Original description"
    ) async throws -> Milestone {
        try await milestoneService.createMilestone(
            name: name,
            description: description,
            project: project
        )
    }

    /// The form as it exists the moment the editor has appeared.
    func loadedForm(for milestone: Milestone) -> MilestoneEditForm {
        var form = MilestoneEditForm()
        form.load(from: milestone)
        return form
    }

    /// Runs the save the editor would run for `form`.
    func save(_ form: MilestoneEditForm, to milestone: Milestone) throws {
        guard let merge = form.merge(against: milestone) else { return }
        try applier.apply(merge, edited: form.edited, to: milestone)
    }
}

// MARK: - Concurrent update regression

/// Regression tests for T-1817.
///
/// `MilestoneEditView` snapshotted both editable fields into `@State` on appear
/// and wrote both back on save, so an external writer's change to the field the
/// user had not touched was silently reverted.
@MainActor @Suite(.serialized)
struct MilestoneEditConcurrentUpdateTests {

    /// Open the editor, let another writer rename the milestone, edit only the
    /// description, save. The rename survives.
    @Test func externalRenameSurvivesDescriptionEdit() async throws {
        let env = try MilestoneEditTestEnv.make()
        let milestone = try await env.makeMilestone()
        var form = env.loadedForm(for: milestone)

        try env.milestoneService.updateMilestone(milestone, name: "Renamed elsewhere", description: nil)

        form.description = "Rewritten by the user"

        let merge = try #require(form.merge(against: milestone))
        #expect(merge.changedFields == [.description])
        #expect(merge.hasConflicts == false)

        try env.save(form, to: milestone)

        #expect(milestone.name == "Renamed elsewhere")
        #expect(milestone.milestoneDescription == "Rewritten by the user")
    }

    /// The mirror case: an external description rewrite survives a rename.
    @Test func externalDescriptionChangeSurvivesNameEdit() async throws {
        let env = try MilestoneEditTestEnv.make()
        let milestone = try await env.makeMilestone()
        var form = env.loadedForm(for: milestone)

        try env.milestoneService.updateMilestone(milestone, name: nil, description: "Rewritten elsewhere")

        form.name = "Renamed by the user"

        let merge = try #require(form.merge(against: milestone))
        #expect(merge.changedFields == [.name])

        try env.save(form, to: milestone)

        #expect(milestone.name == "Renamed by the user")
        #expect(milestone.milestoneDescription == "Rewritten elsewhere")
    }

    /// A save with no form edits at all must not write anything.
    @Test func untouchedFormWritesNothing() async throws {
        let env = try MilestoneEditTestEnv.make()
        let milestone = try await env.makeMilestone()
        let form = env.loadedForm(for: milestone)

        try env.milestoneService.updateMilestone(milestone, name: "Renamed elsewhere", description: nil)

        let merge = try #require(form.merge(against: milestone))
        #expect(merge.hasChanges == false)

        try env.save(form, to: milestone)

        #expect(milestone.name == "Renamed elsewhere")
    }

    /// Clearing the description still removes it — the merge must not read
    /// "emptied" as "untouched".
    @Test func clearingDescriptionStillRemovesIt() async throws {
        let env = try MilestoneEditTestEnv.make()
        let milestone = try await env.makeMilestone()
        var form = env.loadedForm(for: milestone)

        form.description = ""

        let merge = try #require(form.merge(against: milestone))
        #expect(merge.changedFields == [.description])

        try env.save(form, to: milestone)

        #expect(milestone.milestoneDescription == nil)
    }

    /// The editor does not edit status, so a status change made elsewhere is
    /// untouched by a save.
    @Test func externalStatusChangeIsUnaffectedBySave() async throws {
        let env = try MilestoneEditTestEnv.make()
        let milestone = try await env.makeMilestone()
        var form = env.loadedForm(for: milestone)

        try env.milestoneService.updateStatus(milestone, to: .done)

        form.name = "Renamed by the user"
        try env.save(form, to: milestone)

        #expect(milestone.name == "Renamed by the user")
        #expect(milestone.status == .done)
    }

    /// The draft survives a second `onAppear`, matching the project editor's
    /// load-once behaviour (T-1880).
    @Test func draftSurvivesASecondAppearance() async throws {
        let env = try MilestoneEditTestEnv.make()
        let milestone = try await env.makeMilestone()
        var form = env.loadedForm(for: milestone)

        form.name = "Unsaved name"
        form.description = "Unsaved description"
        form.load(from: milestone)

        #expect(form.name == "Unsaved name")
        #expect(form.description == "Unsaved description")
    }
}

// MARK: - Conflict detection

@MainActor @Suite(.serialized)
struct MilestoneEditConflictDetectionTests {

    /// Different values on the same field is a conflict.
    @Test func sameFieldChangedByBothSidesIsAConflict() async throws {
        let env = try MilestoneEditTestEnv.make()
        let milestone = try await env.makeMilestone()
        var form = env.loadedForm(for: milestone)

        try env.milestoneService.updateMilestone(milestone, name: "Renamed elsewhere", description: nil)

        form.name = "Renamed by the user"

        let merge = try #require(form.merge(against: milestone))
        #expect(merge.conflictingFields == [.name])
        #expect(merge.conflictingFieldNames == ["Name"])
    }

    /// Both sides landing on the same value is agreement, not a conflict.
    @Test func sameFieldChangedToSameValueIsNotAConflict() async throws {
        let env = try MilestoneEditTestEnv.make()
        let milestone = try await env.makeMilestone()
        var form = env.loadedForm(for: milestone)

        try env.milestoneService.updateMilestone(milestone, name: "Agreed name", description: nil)

        form.name = "Agreed name"

        let merge = try #require(form.merge(against: milestone))
        #expect(merge.changedFields == [.name])
        #expect(merge.hasConflicts == false)
    }

    /// "Use Updated Values" loads the external value for the conflicting field,
    /// keeps the user's other edit, and re-baselines.
    @Test func adoptingLiveValuesKeepsUnrelatedEdits() async throws {
        let env = try MilestoneEditTestEnv.make()
        let milestone = try await env.makeMilestone()
        var form = env.loadedForm(for: milestone)

        try env.milestoneService.updateMilestone(milestone, name: "Renamed elsewhere", description: nil)

        form.name = "Renamed by the user"
        form.description = "Rewritten by the user"

        let merge = try #require(form.merge(against: milestone))
        form.adoptLiveValues(for: merge, from: milestone)

        #expect(form.name == "Renamed elsewhere")
        #expect(form.description == "Rewritten by the user")

        let rebased = try #require(form.merge(against: milestone))
        #expect(rebased.changedFields == [.description])
        #expect(rebased.hasConflicts == false)
    }

    /// The alert names the fields and both choices.
    @Test func conflictDescriptionNamesFieldsAndChoices() async throws {
        let env = try MilestoneEditTestEnv.make()
        let milestone = try await env.makeMilestone()
        var form = env.loadedForm(for: milestone)

        try env.milestoneService.updateMilestone(milestone, name: "Renamed elsewhere", description: nil)

        form.name = "Renamed by the user"

        let merge = try #require(form.merge(against: milestone))
        let message = merge.conflictDescription(subject: "Milestone")

        #expect(message.contains("Name"))
        #expect(message.contains("this milestone"))
        #expect(message.contains("Keep My Changes"))
    }
}
