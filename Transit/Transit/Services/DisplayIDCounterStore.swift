import Foundation

extension DisplayIDAllocator {
    /// Snapshot of the counter state used for optimistic locking.
    nonisolated struct CounterSnapshot: Sendable {
        let nextDisplayID: Int
        let changeTag: String?
    }

    /// Sendable counter persistence independent of MainActor, allowing actor-backed stores.
    nonisolated protocol CounterStore: Sendable {
        func loadCounter() async throws -> CounterSnapshot
        func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws
    }

}

// MARK: - CounterStore advance

extension DisplayIDAllocator.CounterStore {
    /// Advances the counter so that `nextDisplayID` is at least `target`.
    /// No-op when the counter is already at or past `target`. Uses
    /// compare-and-swap via `saveCounter`, retrying on conflict so a racing
    /// writer that already moved the counter past `target` short-circuits the
    /// loop on the next `loadCounter` read.
    func advanceCounter(toAtLeast target: Int, retryLimit: Int = 5) async throws {
        var attempt = 0
        while attempt < retryLimit {
            attempt += 1
            let snapshot = try await loadCounter()
            if snapshot.nextDisplayID >= target { return }
            do {
                try await saveCounter(nextDisplayID: target, expectedChangeTag: snapshot.changeTag)
                return
            } catch let error as DisplayIDAllocator.Error where error == .conflict {
                continue
            }
        }
        throw DisplayIDAllocator.Error.retriesExhausted
    }
}
