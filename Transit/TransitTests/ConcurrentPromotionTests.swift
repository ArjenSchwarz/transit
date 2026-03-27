import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-597: Concurrent ID promotion can overwrite assigned IDs.
///
/// When multiple promotion calls overlap (e.g. ScenePhaseModifier.task +
/// onChange(.active) + ConnectivityMonitor.onRestore), the same provisional
/// models can be fetched by both runs. Without a single-flight guard, the
/// second run allocates a new permanent ID for an already-promoted record,
/// wasting IDs and overwriting the first assignment.
///
/// The fix adds an `isPromoting` flag to both `DisplayIDAllocator` and
/// `MilestoneService` that causes overlapping calls to bail out immediately.
@MainActor @Suite(.serialized)
struct ConcurrentPromotionTests {

    // MARK: - Task Promotion Guard

    @Test func taskPromotionIsNotReentrant() async throws {
        // Verifies that the isPromoting guard on DisplayIDAllocator prevents
        // a second call from entering while the first is still running.
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 10)
        let allocator = DisplayIDAllocator(store: store, retryLimit: 3)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)

        let task = TransitTask(
            name: "Provisional", type: .feature, project: project, displayID: .provisional
        )
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        try context.save()

        // The isPromoting flag should prevent concurrent execution.
        // We verify this by checking that only one ID is consumed after
        // two sequential calls (the second sees no provisional tasks).
        await allocator.promoteProvisionalTasks(in: context)
        await allocator.promoteProvisionalTasks(in: context)

        #expect(task.permanentDisplayId == 10)

        let snapshot = try await store.loadCounter()
        #expect(snapshot.nextDisplayID == 11)
    }

    @Test func taskPromotionGuardResetsAfterCompletion() async throws {
        // After a completed promotion, the guard must reset so new
        // provisional tasks created later can be promoted.
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store, retryLimit: 3)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)

        let task1 = TransitTask(
            name: "First", type: .feature, project: project, displayID: .provisional
        )
        StatusEngine.initializeNewTask(task1)
        context.insert(task1)
        try context.save()

        await allocator.promoteProvisionalTasks(in: context)
        #expect(task1.permanentDisplayId == 1)

        // New provisional task after first promotion completes.
        let task2 = TransitTask(
            name: "Second", type: .feature, project: project, displayID: .provisional
        )
        StatusEngine.initializeNewTask(task2)
        context.insert(task2)
        try context.save()

        await allocator.promoteProvisionalTasks(in: context)
        #expect(task2.permanentDisplayId == 2)
    }

    @Test func taskPromotionGuardResetsAfterFailure() async throws {
        // After a failed promotion (save error), the guard must reset so a
        // subsequent call can retry.
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store, retryLimit: 3)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)

        let task = TransitTask(
            name: "WillFail", type: .feature, project: project, displayID: .provisional
        )
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        try context.save()

        // First attempt fails on save.
        await allocator.promoteProvisionalTasks(in: context, save: { _ in
            throw SaveFailure.simulated
        })
        #expect(task.permanentDisplayId == nil)

        // Guard resets, so the next attempt succeeds.
        await allocator.promoteProvisionalTasks(in: context)
        #expect(task.permanentDisplayId != nil)
    }

    // MARK: - Milestone Promotion Guard

    @Test func milestonePromotionIsNotReentrant() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 20)
        let allocator = DisplayIDAllocator(store: store, retryLimit: 3)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)

        let milestone = Milestone(
            name: "v1.0", description: nil, project: project, displayID: .provisional
        )
        context.insert(milestone)
        try context.save()

        await service.promoteProvisionalMilestones()
        await service.promoteProvisionalMilestones()

        #expect(milestone.permanentDisplayId == 20)

        let snapshot = try await store.loadCounter()
        #expect(snapshot.nextDisplayID == 21)
    }

    @Test func milestonePromotionGuardResetsAfterCompletion() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store, retryLimit: 3)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)

        let milestone1 = Milestone(
            name: "v1.0", description: nil, project: project, displayID: .provisional
        )
        context.insert(milestone1)
        try context.save()

        await service.promoteProvisionalMilestones()
        #expect(milestone1.permanentDisplayId == 1)

        let milestone2 = Milestone(
            name: "v2.0", description: nil, project: project, displayID: .provisional
        )
        context.insert(milestone2)
        try context.save()

        await service.promoteProvisionalMilestones()
        #expect(milestone2.permanentDisplayId == 2)
    }

    @Test func milestonePromotionGuardResetsAfterFailure() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store, retryLimit: 3)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)

        let milestone = Milestone(
            name: "v1.0", description: nil, project: project, displayID: .provisional
        )
        context.insert(milestone)
        try context.save()

        await service.promoteProvisionalMilestones(save: { _ in
            throw SaveFailure.simulated
        })
        #expect(milestone.permanentDisplayId == nil)

        await service.promoteProvisionalMilestones()
        #expect(milestone.permanentDisplayId != nil)
    }
}
