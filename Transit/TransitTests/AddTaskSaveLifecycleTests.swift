import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1898. Add Task must retain its create operation,
/// cancel it when its macOS window disappears, and distinguish that cancellation
/// from a successful save-driven dismissal.
@MainActor @Suite(.serialized)
struct AddTaskSaveLifecycleTests {

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(
            name: "Lifecycle Project",
            description: "Test project",
            gitRepo: nil,
            colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }

    private func makeDraft(project: Project) -> AddTaskSheet.TaskDraft {
        AddTaskSheet.TaskDraft(
            name: "Lifecycle Task",
            description: nil,
            type: .feature,
            priority: .medium,
            projectID: project.id,
            milestone: nil
        )
    }

    @Test func disappearanceDuringGatedAllocationCancelsCreateBeforeTaskInsertion() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let counterStore = AllocationGatedCounterStore()
        let taskService = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: counterStore)
        )
        let project = makeProject(in: context)
        var lifecycle = AddTaskSaveLifecycle()

        let didBegin = lifecycle.beginSave()
        #expect(didBegin)
        let saveTask = Task { @MainActor in
            try await AddTaskSheet.persist(draft: makeDraft(project: project), taskService: taskService)
        }

        let reachedAllocation = await counterStore.waitUntilAllocationStarts()
        #expect(reachedAllocation, "The test must cancel while display-ID allocation is suspended")
        let didRequestCancellation = lifecycle.cancelForDisappearance()
        #expect(didRequestCancellation)
        saveTask.cancel()
        await counterStore.releaseAllocation()

        await #expect(throws: CancellationError.self) {
            try await saveTask.value
        }

        lifecycle.completeCancellation()
        #expect(lifecycle.blocksDismissal == false)
        #expect(
            try context.fetch(FetchDescriptor<TransitTask>()).isEmpty,
            "Closing Add Task during a gated allocation must not insert a task [T-1898]"
        )
    }

    @Test func successfulCreateDoesNotCancelWhenItsDismissalMakesTheViewDisappear() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let taskService = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore())
        )
        let project = makeProject(in: context)
        var lifecycle = AddTaskSaveLifecycle()

        let didBegin = lifecycle.beginSave()
        #expect(didBegin)
        try await AddTaskSheet.persist(draft: makeDraft(project: project), taskService: taskService)
        let didCompleteSave = lifecycle.completeSave()
        let didRequestCancellation = lifecycle.cancelForDisappearance()
        #expect(didCompleteSave)
        #expect(didRequestCancellation == false)
        #expect(lifecycle.blocksDismissal)
        lifecycle.resetAfterSuccessfulDismissal()
        #expect(lifecycle.blocksDismissal == false)
        let canBeginNextSave = lifecycle.beginSave()
        #expect(canBeginNextSave)
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).count == 1)
    }

    @Test func cancellationPendingBlocksReplacementSaveUntilOriginalTaskSettles() {
        var lifecycle = AddTaskSaveLifecycle()

        let didBegin = lifecycle.beginSave()
        let didRequestCancellation = lifecycle.cancelForDisappearance()
        #expect(didBegin)
        #expect(didRequestCancellation)
        #expect(lifecycle.blocksDismissal == false)
        #expect(lifecycle.isCancellationPending)
        #expect(lifecycle.blocksSaveAction)
        let didBeginReplacementSave = lifecycle.beginSave()
        #expect(didBeginReplacementSave == false)

        lifecycle.completeCancellation()
        #expect(lifecycle.blocksSaveAction == false)
        let didBeginAfterCancellation = lifecycle.beginSave()
        #expect(didBeginAfterCancellation)
    }

    @Test func failedSaveReenablesDismissalAndRetry() {
        var lifecycle = AddTaskSaveLifecycle()

        let didBegin = lifecycle.beginSave()
        lifecycle.completeFailure()
        #expect(didBegin)
        #expect(lifecycle.blocksDismissal == false)

        let didRetry = lifecycle.beginSave()
        #expect(didRetry)
    }
}
