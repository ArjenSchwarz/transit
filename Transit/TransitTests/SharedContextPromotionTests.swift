import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression test for T-158: ScenePhaseModifier must use the same ModelContext
/// as the services. Previously, a new ModelContext was created inline on every
/// SwiftUI body evaluation, leading to context mismatch and wasted allocations.
@MainActor @Suite(.serialized)
struct SharedContextPromotionTests {

    // MARK: - Shared context: promotion visible to service

    @Test func promotionOnSharedContextIsVisibleToService() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store)

        let project = Project(name: "P", description: "Test", gitRepo: nil, colorHex: "#000000")
        context.insert(project)

        // Create a task with a provisional display ID
        let task = TransitTask(
            name: "Provisional Task", type: .feature, project: project, displayID: .provisional
        )
        context.insert(task)
        try context.save()

        #expect(task.permanentDisplayId == nil, "Task should start with no permanent ID")

        // Promote using the SAME context the service uses (the fix)
        await allocator.promoteProvisionalTasks(in: context)

        // The task fetched through the service's context should have a permanent ID
        let tasks = try context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 1)
        #expect(tasks[0].permanentDisplayId == 1, "Promoted ID should be visible in the shared context")
    }

    // MARK: - Separate context: promotion may not be visible without merge

    @Test func promotionOnSeparateContextIsNotImmediatelyVisibleToService() async throws {
        // This test demonstrates the bug scenario: using a separate context for
        // promotion means the service context doesn't see the changes immediately.
        let serviceContext = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store)

        let project = Project(name: "P", description: "Test", gitRepo: nil, colorHex: "#000000")
        serviceContext.insert(project)

        let task = TransitTask(
            name: "Provisional Task", type: .feature, project: project, displayID: .provisional
        )
        serviceContext.insert(task)
        try serviceContext.save()

        // Create a SEPARATE context (simulating the old bug where ModelContext(container)
        // was called inline in body). Both contexts point to the same in-memory store,
        // but the separate context fetches its own object graph.
        let separateContext = ModelContext(serviceContext.container)
        await allocator.promoteProvisionalTasks(in: separateContext)

        // The service context's in-memory object still has the old provisional value
        // because the promotion happened in a different context's object graph.
        #expect(
            task.permanentDisplayId == nil,
            "Service context object should NOT see promotion from a separate context without a merge"
        )
    }
}
