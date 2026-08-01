import Foundation
import SwiftData
import Testing
@testable import Transit

/// Observes the allocation gate's queued-waiter lifecycle. The tests wait for
/// both events before releasing the holder, so cancellation cannot pass merely
/// by short-circuiting before it reaches the waiter queue.
private actor WaiterQueueProbe {
    private var hasQueuedWaiter = false
    private var hasRemovedWaiter = false
    private var queuedContinuation: CheckedContinuation<Void, Never>?
    private var removedContinuation: CheckedContinuation<Void, Never>?

    func recordQueuedWaiter() {
        hasQueuedWaiter = true
        queuedContinuation?.resume()
        queuedContinuation = nil
    }

    func recordRemovedWaiter() {
        hasRemovedWaiter = true
        removedContinuation?.resume()
        removedContinuation = nil
    }

    func waitUntilWaiterQueued() async {
        guard !hasQueuedWaiter else { return }
        await withCheckedContinuation { queuedContinuation = $0 }
    }

    func waitUntilWaiterRemoved() async {
        guard !hasRemovedWaiter else { return }
        await withCheckedContinuation { removedContinuation = $0 }
    }
}

/// Regression tests for cancelled task and milestone creates (T-1426, T-1765).
///
/// T-1426 covered cancellation while queued behind a contended allocation gate.
/// T-1765 closes two remaining paths: an already-cancelled caller could acquire a
/// free gate, and cancellation during a non-cooperative successful allocation was
/// not observed before insertion.
///
/// The tests cover pre-cancelled uncontended creates, cancellation while the
/// allocation body succeeds, and cancellation while queued behind a gate holder.
/// In every case cancellation must surface as `CancellationError` and must not
/// mutate persistent state. Genuine CloudKit/offline allocation failures still
/// fall back to provisional IDs in the existing allocator/concurrency suites.
@MainActor @Suite(.serialized)
struct CancelledCreateTests {

    // MARK: - Test doubles

    /// A non-cancellation-cooperative start barrier. Cancelling a task while it
    /// waits here ensures the create path begins with cancellation already set.
    private actor StartGate {
        private var isReleased = false
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            guard !isReleased else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            isReleased = true
            continuation?.resume()
            continuation = nil
        }
    }

    /// A counter store whose **first** `loadCounter` call blocks until the test
    /// explicitly releases it. Because `allocateNextID` reads the counter while
    /// holding the allocation gate, blocking the first read keeps the gate held —
    /// forcing any concurrent allocation to queue behind it. This deterministically
    /// reproduces the "contended gate" window the ticket describes.
    private actor GatedCounterStore: DisplayIDAllocator.CounterStore {
        private var nextDisplayID: Int
        private var changeTag = 0
        private var saveAttempts = 0

        var saveAttemptCount: Int { saveAttempts }

        private var firstLoadStarted = false
        private var firstLoadReached: CheckedContinuation<Void, Never>?

        private var hasReleased = false
        private var releaseContinuation: CheckedContinuation<Void, Never>?

        init(initialNextDisplayID: Int = 1) {
            self.nextDisplayID = initialNextDisplayID
        }

        /// Suspends until the first `loadCounter` call has been entered, i.e. the
        /// holder now owns the allocation gate.
        func waitUntilGateHeld() async {
            if firstLoadStarted { return }
            await withCheckedContinuation { firstLoadReached = $0 }
        }

        /// Lets the blocked first `loadCounter` call proceed so the holder can
        /// finish and the gate is released — preventing a leaked continuation.
        func releaseGate() {
            hasReleased = true
            releaseContinuation?.resume()
            releaseContinuation = nil
        }

        func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
            if !firstLoadStarted {
                firstLoadStarted = true
                firstLoadReached?.resume()
                firstLoadReached = nil

                if !hasReleased {
                    await withCheckedContinuation { releaseContinuation = $0 }
                }
            }
            return DisplayIDAllocator.CounterSnapshot(
                nextDisplayID: nextDisplayID,
                changeTag: "\(changeTag)"
            )
        }

        func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
            saveAttempts += 1
            guard expectedChangeTag == "\(changeTag)" else {
                throw DisplayIDAllocator.Error.conflict
            }
            self.nextDisplayID = nextDisplayID
            changeTag += 1
        }
    }

    // MARK: - Helpers

    private func makeProject(in context: ModelContext, name: String = "P") -> Project {
        let project = Project(name: name, description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    // MARK: - Tasks

    /// A create that begins already cancelled must fail before an uncontended
    /// allocation gate reaches the counter store.
    @Test func preCancelledUncontendedTaskCreateDoesNotPersistRecord() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let startGate = StartGate()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeProject(in: context)

        let operation = Task { @MainActor in
            await startGate.wait()
            _ = try await service.createTask(
                name: "Cancelled", description: nil, type: .feature, project: project
            )
        }
        operation.cancel()
        await startGate.release()

        await #expect(throws: CancellationError.self) {
            try await operation.value
        }

        let storeWasNeverAccessed = await store.wasNeverAccessed
        #expect(storeWasNeverAccessed, "A pre-cancelled create must not enter the counter store")
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }

    /// Cancellation while a non-cooperative counter store completes a successful
    /// allocation must still abort before task insertion.
    @Test func taskCancelledDuringSuccessfulAllocationDoesNotPersistRecord() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let store = GatedCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeProject(in: context)

        let operation = Task { @MainActor in
            _ = try await service.createTask(
                name: "Cancelled", description: nil, type: .feature, project: project
            )
        }
        await store.waitUntilGateHeld()
        operation.cancel()
        await store.releaseGate()

        await #expect(throws: CancellationError.self) {
            try await operation.value
        }

        let saveAttempts = await store.saveAttemptCount
        #expect(saveAttempts == 1, "The allocation must succeed before cancellation is observed")
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }

    /// A task create that is cancelled while queued behind a gate-holding create
    /// must throw `CancellationError` and must NOT persist any (provisional) task.
    @Test func cancelledTaskCreateDoesNotPersistProvisionalRecord() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let store = GatedCounterStore()
        let queueProbe = WaiterQueueProbe()
        let allocator = DisplayIDAllocator(
            store: store,
            onWaiterQueued: { Task { await queueProbe.recordQueuedWaiter() } },
            onWaiterCancelled: { Task { await queueProbe.recordRemovedWaiter() } }
        )
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeProject(in: context)

        // Holder: acquires the allocation gate and blocks inside the counter store.
        let holder = Task { @MainActor in
            _ = try await service.createTask(
                name: "Holder", description: nil, type: .feature, project: project
            )
        }
        await store.waitUntilGateHeld()

        // Contender: queues on the gate, then is cancelled while waiting.
        let contender = Task { @MainActor in
            _ = try await service.createTask(
                name: "Cancelled", description: nil, type: .feature, project: project
            )
        }
        await queueProbe.waitUntilWaiterQueued()
        contender.cancel()
        await queueProbe.waitUntilWaiterRemoved()

        await #expect(throws: CancellationError.self) {
            try await contender.value
        }

        // Let the holder finish so its allocation gate is released cleanly.
        await store.releaseGate()
        _ = try await holder.value

        let tasks = try context.fetch(FetchDescriptor<TransitTask>())
        #expect(
            !tasks.contains { $0.name == "Cancelled" },
            "A cancelled create must not insert a task record"
        )
        #expect(
            tasks.count == 1,
            "Only the holder task should be persisted, found \(tasks.count)"
        )
    }

    // MARK: - Milestones

    /// A milestone create that begins already cancelled must fail before an
    /// uncontended allocation gate reaches the counter store.
    @Test func preCancelledUncontendedMilestoneCreateDoesNotPersistRecord() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let startGate = StartGate()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let project = makeProject(in: context)

        let operation = Task { @MainActor in
            await startGate.wait()
            _ = try await service.createMilestone(
                name: "Cancelled", description: nil, project: project
            )
        }
        operation.cancel()
        await startGate.release()

        await #expect(throws: CancellationError.self) {
            try await operation.value
        }

        let storeWasNeverAccessed = await store.wasNeverAccessed
        #expect(storeWasNeverAccessed, "A pre-cancelled create must not enter the counter store")
        #expect(try context.fetch(FetchDescriptor<Milestone>()).isEmpty)
    }

    /// Cancellation while a non-cooperative counter store completes a successful
    /// allocation must still abort before milestone insertion.
    @Test func milestoneCancelledDuringSuccessfulAllocationDoesNotPersistRecord() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let store = GatedCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let project = makeProject(in: context)

        let operation = Task { @MainActor in
            _ = try await service.createMilestone(
                name: "Cancelled", description: nil, project: project
            )
        }
        await store.waitUntilGateHeld()
        operation.cancel()
        await store.releaseGate()

        await #expect(throws: CancellationError.self) {
            try await operation.value
        }

        let saveAttempts = await store.saveAttemptCount
        #expect(saveAttempts == 1, "The allocation must succeed before cancellation is observed")
        #expect(try context.fetch(FetchDescriptor<Milestone>()).isEmpty)
    }

    /// A milestone create that is cancelled while queued behind a gate-holding
    /// create must throw `CancellationError` and must NOT persist any record.
    @Test func cancelledMilestoneCreateDoesNotPersistProvisionalRecord() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let store = GatedCounterStore()
        let queueProbe = WaiterQueueProbe()
        let allocator = DisplayIDAllocator(
            store: store,
            onWaiterQueued: { Task { await queueProbe.recordQueuedWaiter() } },
            onWaiterCancelled: { Task { await queueProbe.recordRemovedWaiter() } }
        )
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let project = makeProject(in: context)

        let holder = Task { @MainActor in
            _ = try await service.createMilestone(
                name: "Holder", description: nil, project: project
            )
        }
        await store.waitUntilGateHeld()

        let contender = Task { @MainActor in
            _ = try await service.createMilestone(
                name: "Cancelled", description: nil, project: project
            )
        }
        await queueProbe.waitUntilWaiterQueued()
        contender.cancel()
        await queueProbe.waitUntilWaiterRemoved()

        await #expect(throws: CancellationError.self) {
            try await contender.value
        }

        await store.releaseGate()
        _ = try await holder.value

        let milestones = try context.fetch(FetchDescriptor<Milestone>())
        #expect(
            !milestones.contains { $0.name == "Cancelled" },
            "A cancelled create must not insert a milestone record"
        )
        #expect(
            milestones.count == 1,
            "Only the holder milestone should be persisted, found \(milestones.count)"
        )
    }
}
