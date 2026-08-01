import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskEditViewMilestoneTests {

    private func makeMilestoneService() throws -> (MilestoneService, ModelContext) {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        return (service, context)
    }

    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    @Test func availableMilestonesIncludesSelectedClosedMilestone() async throws {
        let (milestoneService, context) = try makeMilestoneService()
        let project = makeProject(in: context)
        let openMilestone = try await milestoneService.createMilestone(name: "Open", description: nil, project: project)
        let doneMilestone = try await milestoneService.createMilestone(name: "Done", description: nil, project: project)
        try milestoneService.updateStatus(doneMilestone, to: .done)

        let availableMilestones = TaskEditView.availableMilestones(
            project: project,
            selectedMilestone: doneMilestone,
            milestoneService: milestoneService
        )

        #expect(Set(availableMilestones.map(\.id)) == [openMilestone.id, doneMilestone.id])
    }

    @Test func availableMilestonesDoesNotDuplicateSelectedOpenMilestone() async throws {
        let (milestoneService, context) = try makeMilestoneService()
        let project = makeProject(in: context)
        let openMilestone = try await milestoneService.createMilestone(name: "Open", description: nil, project: project)

        let availableMilestones = TaskEditView.availableMilestones(
            project: project,
            selectedMilestone: openMilestone,
            milestoneService: milestoneService
        )

        #expect(availableMilestones.map(\.id) == [openMilestone.id])
    }

    @Test func availableMilestonesExcludesSelectedMilestoneFromAnotherProject() async throws {
        let (milestoneService, context) = try makeMilestoneService()
        let currentProject = makeProject(in: context, name: "Current")
        let otherProject = makeProject(in: context, name: "Other")
        let openMilestone = try await milestoneService.createMilestone(
            name: "Open",
            description: nil,
            project: currentProject
        )
        let otherMilestone = try await milestoneService.createMilestone(
            name: "Other Closed",
            description: nil,
            project: otherProject
        )
        try milestoneService.updateStatus(otherMilestone, to: .done)

        let availableMilestones = TaskEditView.availableMilestones(
            project: currentProject,
            selectedMilestone: otherMilestone,
            milestoneService: milestoneService
        )

        #expect(availableMilestones.map(\.id) == [openMilestone.id])
    }

    /// A rebase merges fields independently, so "Use Updated Values" can pair an
    /// externally moved project with a milestone the user picked under the old
    /// one. Carrying that pair into the draft makes every later save fail
    /// `MilestoneService` project-match validation, so the milestone is dropped.
    @Test func rebasedMilestoneIsDroppedWhenItBelongsToAnotherProject() async throws {
        let (milestoneService, context) = try makeMilestoneService()
        let originalProject = makeProject(in: context, name: "Original")
        let externalProject = makeProject(in: context, name: "Moved elsewhere")
        let userPick = try await milestoneService.createMilestone(
            name: "Picked by the user",
            description: nil,
            project: originalProject
        )

        let rebased = TaskEditView.rebasedMilestone(
            milestoneID: userPick.id,
            projectID: externalProject.id,
            candidates: [userPick, nil]
        )

        #expect(rebased == nil)
    }

    /// The ordinary case: the rebased milestone still belongs to the rebased
    /// project, so the user's non-conflicting pick survives the rebase.
    @Test func rebasedMilestoneIsKeptWhenItMatchesTheRebasedProject() async throws {
        let (milestoneService, context) = try makeMilestoneService()
        let project = makeProject(in: context)
        let userPick = try await milestoneService.createMilestone(
            name: "Picked by the user",
            description: nil,
            project: project
        )

        let rebased = TaskEditView.rebasedMilestone(
            milestoneID: userPick.id,
            projectID: project.id,
            candidates: [userPick, nil]
        )

        #expect(rebased?.id == userPick.id)
    }

    /// An externally assigned milestone is resolved from the live task when the
    /// user never picked one.
    @Test func rebasedMilestoneResolvesTheLiveTaskMilestone() async throws {
        let (milestoneService, context) = try makeMilestoneService()
        let project = makeProject(in: context)
        let externalPick = try await milestoneService.createMilestone(
            name: "Assigned by MCP",
            description: nil,
            project: project
        )

        let rebased = TaskEditView.rebasedMilestone(
            milestoneID: externalPick.id,
            projectID: project.id,
            candidates: [nil, externalPick]
        )

        #expect(rebased?.id == externalPick.id)
    }

    /// No milestone in the rebased draft means no selection, regardless of what
    /// either side had before.
    @Test func rebasedMilestoneIsNilWhenTheDraftHasNoMilestone() async throws {
        let (milestoneService, context) = try makeMilestoneService()
        let project = makeProject(in: context)
        let candidate = try await milestoneService.createMilestone(
            name: "Previously selected",
            description: nil,
            project: project
        )

        let rebased = TaskEditView.rebasedMilestone(
            milestoneID: nil,
            projectID: project.id,
            candidates: [candidate, nil]
        )

        #expect(rebased == nil)
    }
}
