import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskEditViewMilestoneTests {

    private func makeMilestoneService() throws -> (MilestoneService, ModelContext) {
        let context = try TestModelContainer.newContext()
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
}
