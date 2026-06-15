import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1426: "Cancelled creates still persist provisional records".
///
/// The T-1395 allocation gate (`DisplayIDAllocator`'s `AllocationGate`) propagates
/// `CancellationError` when a caller is cancelled while waiting for display-ID
/// allocation. Both creation services previously caught *every* allocation error
/// and converted it into a `.provisional` ID, which meant a cancelled create still
/// inserted and saved a new provisional record instead of aborting.
///
/// These tests contend the allocation gate: a first ("holder") create acquires the
/// gate and blocks inside the counter store, so a second create queues behind it.
/// Cancelling the queued create must surface `CancellationError` and must NOT mutate
/// persistent state. Genuine allocation failures (CloudKit/offline) still fall back
/// to provisional IDs — covered by the existing allocator/concurrency suites.
@MainActor @Suite(.serialized)
struct CancelledCreateTests {

    // MARK: - Test double

    /// A counter store whose **first** `loadCounter` call blocks until the test
    /// explicitly releases it. Because `allocateNextID` reads the counter while
    /// holding the allocation gate, blocking the first read keeps the gate held —
    /// forcing any concurrent allocation to queue behind it. This deterministically
    /// reproduces the "contended gate" window the ticket describes.
    private actor GatedCounterStore: DisplayIDAllocator.CounterStore {
        private var nextDisplayID: Int
        private var changeTag = 0

        private var firstLoadStarted = false
        private var hasSignaledFirstLoad = false
        private var firstLoadReached: CheckedContinuation<Void, Never>?

        private var hasReleased = false
        private var releaseContinuation: CheckedContinuation<Void, Never>?

        init(initialNextDisplayID: Int = 1) {
            self.nextDisplayID = initialNextDisplayID
        }

        /// Suspends until the first `loadCounter` call has been entered, i.e. the
        /// holder now owns the allocation gate.
        func waitUntilGateHeld() async {
            if hasSignaledFirstLoad { return }
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
                hasSignaledFirstLoad = true
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

    /// A task create that is cancelled while queued behind a gate-holding create
    /// must throw `CancellationError` and must NOT persist any (provisional) task.
    @Test func cancelledTaskCreateDoesNotPersistProvisionalRecord() async throws {
        let context = try TestModelContainer.newContext()
        let store = GatedCounterStore()
        let allocator = DisplayIDAllocator(store: store)
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
        contender.cancel()

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

    /// A milestone create that is cancelled while queued behind a gate-holding
    /// create must throw `CancellationError` and must NOT persist any record.
    @Test func cancelledMilestoneCreateDoesNotPersistProvisionalRecord() async throws {
        let context = try TestModelContainer.newContext()
        let store = GatedCounterStore()
        let allocator = DisplayIDAllocator(store: store)
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
        contender.cancel()

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
