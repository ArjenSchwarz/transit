import Foundation
import Testing
@testable import Transit

@MainActor
struct CounterStoreAdvanceTests {

    // MARK: - No-op when already past target

    @Test func noOpWhenCounterAlreadyAtTarget() async throws {
        let store = InMemoryCounterStore(initialNextDisplayID: 50)

        try await store.advanceCounter(toAtLeast: 50)

        let snapshot = try await store.loadCounter()
        #expect(snapshot.nextDisplayID == 50)
        let attempts = await store.saveAttemptCount
        #expect(attempts == 0, "Counter at target should not write")
    }

    @Test func noOpWhenCounterAlreadyPastTarget() async throws {
        let store = InMemoryCounterStore(initialNextDisplayID: 100)

        try await store.advanceCounter(toAtLeast: 50)

        let snapshot = try await store.loadCounter()
        #expect(snapshot.nextDisplayID == 100, "Counter must not be moved backwards")
        let attempts = await store.saveAttemptCount
        #expect(attempts == 0)
    }

    // MARK: - Advance when behind

    @Test func advancesCounterWhenBehind() async throws {
        let store = InMemoryCounterStore(initialNextDisplayID: 5)

        try await store.advanceCounter(toAtLeast: 42)

        let snapshot = try await store.loadCounter()
        #expect(snapshot.nextDisplayID == 42)
        let attempts = await store.saveAttemptCount
        #expect(attempts == 1)
    }

    // MARK: - Retries on conflict

    @Test func retriesAndSucceedsOnTransientConflict() async throws {
        let store = InMemoryCounterStore(initialNextDisplayID: 10)
        await store.enqueueSaveOutcomes([.conflict, .success])

        try await store.advanceCounter(toAtLeast: 20)

        let snapshot = try await store.loadCounter()
        #expect(snapshot.nextDisplayID == 20)
        let attempts = await store.saveAttemptCount
        #expect(attempts == 2, "First conflict, second success")
    }

    // MARK: - Throws after retry limit

    @Test func throwsRetriesExhaustedAfterRetryLimit() async throws {
        let store = InMemoryCounterStore(initialNextDisplayID: 10)
        await store.enqueueSaveOutcomes(Array(repeating: .conflict, count: 10))

        await #expect(throws: DisplayIDAllocator.Error.retriesExhausted) {
            try await store.advanceCounter(toAtLeast: 20, retryLimit: 3)
        }

        let attempts = await store.saveAttemptCount
        #expect(attempts == 3)
    }

    // MARK: - Re-read short-circuit when racing writer moved past target

    @Test func shortCircuitsWhenRacingWriterAdvancedPastTarget() async throws {
        // Counter starts at 10. After the first attempt encounters a conflict,
        // a racing writer advances the store to 100. The next loadCounter
        // returns nextDisplayID >= target, so advance returns without writing.
        let store = AdvancingCounterStore(initialNextDisplayID: 10, postConflictNextID: 100)

        try await store.advanceCounter(toAtLeast: 50)

        let snapshot = try await store.loadCounter()
        #expect(snapshot.nextDisplayID == 100, "Racing writer's value preserved")
        let attempts = await store.saveAttemptCount
        #expect(attempts == 1, "Only the first conflicting save attempt; loop short-circuits on re-read")
    }
}

// MARK: - Test Helper Store

/// A counter store that returns conflict on the first save, then on the next
/// loadCounter call returns a value advanced by a racing writer. Used to verify
/// the post-conflict re-read short-circuit in `advanceCounter`.
private actor AdvancingCounterStore: DisplayIDAllocator.CounterStore {
    private var nextDisplayID: Int
    private let postConflictNextID: Int
    private var changeTag: Int = 0
    private var attemptCount: Int = 0
    private var hasConflicted = false

    init(initialNextDisplayID: Int, postConflictNextID: Int) {
        self.nextDisplayID = initialNextDisplayID
        self.postConflictNextID = postConflictNextID
    }

    var saveAttemptCount: Int { attemptCount }

    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        DisplayIDAllocator.CounterSnapshot(nextDisplayID: nextDisplayID, changeTag: "\(changeTag)")
    }

    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
        attemptCount += 1
        if !hasConflicted {
            hasConflicted = true
            // Simulate a racing writer that advanced the counter past the target.
            self.nextDisplayID = postConflictNextID
            changeTag += 1
            throw DisplayIDAllocator.Error.conflict
        }
        self.nextDisplayID = nextDisplayID
        changeTag += 1
    }
}
