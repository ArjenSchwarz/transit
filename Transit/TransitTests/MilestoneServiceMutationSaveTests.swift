import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MilestoneServiceMutationSaveTests {

    @Test func setMilestoneRollsBackWhenInjectedSaveFails() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = Project(name: "Transit", description: "", gitRepo: nil, colorHex: "#000000")
        let milestone = Milestone(name: "Beta", description: nil, project: project, displayID: .permanent(1))
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(1))
        StatusEngine.initializeNewTask(task)
        context.insert(project)
        context.insert(milestone)
        context.insert(task)
        try context.save()

        let service = MilestoneService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore()),
            mutationSave: { _ in throw SaveFailure.simulated }
        )

        #expect(throws: SaveFailure.self) {
            try service.setMilestone(milestone, on: task)
        }
        #expect(task.milestone == nil)
        #expect(!context.hasChanges)
    }
}
