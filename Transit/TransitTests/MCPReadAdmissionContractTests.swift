#if os(macOS)
import Foundation
import NIOConcurrencyHelpers
import Testing
@testable import Transit

/// Calls the actual admission API; receipts follow cleanup and permit removal.
@Suite(.serialized)
nonisolated struct MCPReadAdmissionContractTests {
    @Test @concurrent func duplicateLiveIdentityCannotStartOrReplaceAnotherWorker() async {
        let coordinator = MCPReadCoordinator(maxOperations: 2)
        let gate = AdmissionGate()
        let admission = MCPReadAdmission()
        let first = Task {
            await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
                                      admission: admission) { _ in
                await gate.started()
                await gate.wait()
                return Self.result("first")
            }
        }
        await gate.waitUntilStarted()
        let duplicateStarted = NIOLockedValueBox(false)
        let duplicate = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
                                                  admission: admission) { _ in
            duplicateStarted.withLockedValue { $0 = true }
            return Self.result("duplicate")
        }
        #expect(duplicate == Data("busy".utf8))
        #expect(!duplicateStarted.withLockedValue { $0 })
        #expect(coordinator.unfinishedCount == 1)
        await gate.release()
        #expect(await first.value == Data("first".utf8))
        await Self.drain(coordinator)
    }

    @Test @concurrent func physicalReceiptFollowsCleanupAndPermitRemoval() async {
        let coordinator = MCPReadCoordinator(maxOperations: 1)
        let gate = AdmissionGate()
        let cleaned = NIOLockedValueBox(false)
        let receiptState = NIOLockedValueBox<[Bool]>([])
        let admission = MCPReadAdmission(physicalCompletion: {
            receiptState.withLockedValue { $0 = [cleaned.withLockedValue { $0 }, coordinator.unfinishedCount == 0] }
        })
        let call = Task {
            await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
                                      admission: admission) { _ in
                await gate.started()
                await gate.wait()
                defer { cleaned.withLockedValue { $0 = true } }
                return Self.result("late")
            }
        }
        await gate.waitUntilStarted()
        coordinator.stop()
        #expect(await call.value == Data("timeout".utf8))
        #expect(receiptState.withLockedValue { $0 }.isEmpty)
        #expect(coordinator.unfinishedCount == 1)
        coordinator.start()
        await gate.release()
        await Self.drain(coordinator)
        // Permit removal precedes the outside-lock receipt callback; await each independently.
        let receiptDeadline = ContinuousClock.now + .seconds(1)
        while receiptState.withLockedValue({ $0.isEmpty }) && .now < receiptDeadline { await Task.yield() }
        #expect(receiptState.withLockedValue { $0 } == [true, true])
    }

    private static func result(_ value: String) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: Data(value.utf8), publications: [],
            publicationErrors: .init(busy: Data("busy".utf8), expired: Data("expired".utf8),
                                     capacity: Data("capacity".utf8)))
    }

    private static func drain(_ coordinator: MCPReadCoordinator) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while coordinator.unfinishedCount != 0 && .now < deadline { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0)
    }
}

private actor AdmissionGate {
    private var didStart = false
    private var open = false
    private var starters: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func started() {
        didStart = true
        let pending = starters
        starters.removeAll()
        for continuation in pending { continuation.resume() }
    }
    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { starters.append($0) }
    }
    func wait() async {
        if open { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        open = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending { continuation.resume() }
    }
}
#endif
