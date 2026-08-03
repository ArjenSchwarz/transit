import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression coverage for T-2037: Add Task must revalidate an optional
/// milestone immediately before insertion, because a peer context can close
/// the selected milestone while task creation awaits display-ID allocation.
@MainActor @Suite(.serialized)
struct AddTaskStaleMilestoneTests {

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(
            name: "Test Project",
            description: "A test project",
            gitRepo: nil,
            colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }

    private func makeMilestone(in context: ModelContext, project: Project) -> Milestone {
        let milestone = Milestone(
            name: "v1.0",
            description: nil,
            project: project,
            displayID: .permanent(1)
        )
        context.insert(milestone)
        return milestone
    }

    @Test(arguments: [MilestoneStatus.done, .abandoned])
    func persistRejectsMilestoneClosedAfterSelectionBeforeSaveWithoutInsertingTask(
        terminalStatus: MilestoneStatus
    ) async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let allocationStore = AllocationGatedCounterStore()
        let taskService = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: allocationStore)
        )
        let project = makeProject(in: context)
        let selectedMilestone = makeMilestone(in: context, project: project)
        try context.save()

        let draft = AddTaskSheet.TaskDraft(
            name: "Stale Milestone Task",
            description: nil,
            type: .feature,
            priority: .medium,
            projectID: project.id,
            milestone: selectedMilestone
        )
        let persistence = Task { @MainActor in
            try await AddTaskSheet.persist(draft: draft, taskService: taskService)
        }

        #expect(await allocationStore.waitUntilAllocationStarts())

        let selectedMilestoneID = selectedMilestone.id
        let peerContext = ModelContext(testContainer.container)
        let peerMilestone = try #require(try peerContext.fetch(FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == selectedMilestoneID }
        )).first)
        peerMilestone.status = terminalStatus
        try peerContext.save()

        #expect(selectedMilestone.status == .open, "The selected model must remain stale in its context")
        await allocationStore.releaseAllocation()

        do {
            try await persistence.value
            Issue.record("Expected persistence to reject the now-terminal milestone")
        } catch let error as TaskService.Error {
            #expect(error == .milestoneNotOpen)
        } catch {
            Issue.record("Expected milestoneNotOpen, got \(error)")
        }

        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
        let committedContext = ModelContext(testContainer.container)
        #expect(try committedContext.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }
}
