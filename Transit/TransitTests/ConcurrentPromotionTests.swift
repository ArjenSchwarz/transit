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

    @Test func taskPromotionSecondCallIsNoOp() async throws {
        // Verifies that a second sequential promotion call does not allocate
        // duplicate IDs. The first call promotes all provisional tasks; the
        // second finds nothing to promote and exits cleanly.
        //
        // Note: This does not exercise the isPromoting guard directly because
        // Swift's cooperative concurrency model completes the first call before
        // the second begins. True concurrent overlap would require injecting a
        // suspension point inside promoteProvisionalTasks, which is not worth
        // the production-code complexity. The guard is tested indirectly via
        // the GuardResetsAfterFailure/Completion tests below.
        let testContainer = try TestModelContainer()
        let context = testContainer.context
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

        await allocator.promoteProvisionalTasks(in: context)
        await allocator.promoteProvisionalTasks(in: context)

        #expect(task.permanentDisplayId == 10)

        let snapshot = try await store.loadCounter()
        #expect(snapshot.nextDisplayID == 11)
    }

    @Test func taskPromotionGuardResetsAfterCompletion() async throws {
        // After a completed promotion, the guard must reset so new
        // provisional tasks created later can be promoted.
        let testContainer = try TestModelContainer()
        let context = testContainer.context
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
        let testContainer = try TestModelContainer()
        let context = testContainer.context
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

    @Test func milestonePromotionSecondCallIsNoOp() async throws {
        // Verifies that a second sequential promotion call does not allocate
        // duplicate IDs. See taskPromotionSecondCallIsNoOp for the rationale
        // on why this does not exercise the guard directly.
        let testContainer = try TestModelContainer()
        let context = testContainer.context
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
        let testContainer = try TestModelContainer()
        let context = testContainer.context
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
        let testContainer = try TestModelContainer()
        let context = testContainer.context
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

    // MARK: - Cross-device peer merge during allocation (T-2020)

    @Test func taskPeerPromotionDuringAllocationIsPreserved() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let gateStore = AllocationGatedCounterStore(initialNextDisplayID: 100)
        let allocator = DisplayIDAllocator(store: gateStore)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        let task = TransitTask(
            name: "Synced provisional", type: .feature, project: project, displayID: .provisional
        )
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        try context.save()

        let taskID = task.id
        let peerContext = ModelContext(testContainer.container)
        let peerTask = try #require(try peerContext.fetch(FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == taskID }
        )).first)

        var promotionSaveCount = 0
        let promotion = Task { @MainActor in
            await allocator.promoteProvisionalTasks(in: context, save: { context in
                promotionSaveCount += 1
                try context.save()
            })
        }
        #expect(await gateStore.waitUntilAllocationStarts(), "Task allocation never parked")

        peerTask.permanentDisplayId = 900
        try peerContext.save()
        await gateStore.releaseAllocation()
        await promotion.value

        #expect(promotionSaveCount == 0,
                "Task promotion must not save after a peer assigns a permanent ID")
        let probe = ModelContext(testContainer.container)
        let storedTask = try #require(try probe.fetch(FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == taskID }
        )).first)
        #expect(storedTask.permanentDisplayId == 900,
                "A peer's permanent task ID must not be overwritten after allocation resumes")
        #expect(await gateStore.currentNextDisplayID() == 101,
                "The allocated counter value is deliberately consumed when the peer wins")
    }

    @Test func milestonePeerPromotionDuringAllocationIsPreserved() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let gateStore = AllocationGatedCounterStore(initialNextDisplayID: 200)
        let allocator = DisplayIDAllocator(store: gateStore)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        let milestone = Milestone(
            name: "Synced provisional", description: nil, project: project, displayID: .provisional
        )
        context.insert(milestone)
        try context.save()

        let milestoneID = milestone.id
        let peerContext = ModelContext(testContainer.container)
        let peerMilestone = try #require(try peerContext.fetch(FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == milestoneID }
        )).first)

        var promotionSaveCount = 0
        let promotion = Task { @MainActor in
            await service.promoteProvisionalMilestones(save: { context in
                promotionSaveCount += 1
                try context.save()
            })
        }
        #expect(await gateStore.waitUntilAllocationStarts(), "Milestone allocation never parked")

        peerMilestone.permanentDisplayId = 901
        try peerContext.save()
        await gateStore.releaseAllocation()
        await promotion.value

        #expect(promotionSaveCount == 0,
                "Milestone promotion must not save after a peer assigns a permanent ID")
        let probe = ModelContext(testContainer.container)
        let storedMilestone = try #require(try probe.fetch(FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == milestoneID }
        )).first)
        #expect(storedMilestone.permanentDisplayId == 901,
                "A peer's permanent milestone ID must not be overwritten after allocation resumes")
        #expect(await gateStore.currentNextDisplayID() == 201,
                "The allocated counter value is deliberately consumed when the peer wins")
    }
}
