#if os(macOS)
import Foundation
import NIOConcurrencyHelpers
import Testing
@testable import Transit

/// Interface-capability RED for the new admission value; production binding belongs to task 13.
@Suite(.serialized)
nonisolated struct MCPReadAdmissionContractTests {
    @Test @concurrent func duplicateLiveIdentityCannotStartOrReplaceAnotherWorker() async {
        let coordinator = MCPReadCoordinator(maxOperations: 2)
        let gate = AdmissionGate()
        let admission = MCPReadAdmission()
        let first = Task {
            await Self.baseline(coordinator, admission: admission) { _ in
                await gate.started()
                await gate.wait()
                return Self.result("first")
            }
        }
        await gate.waitUntilStarted()
        let duplicateStarted = NIOLockedValueBox(false)
        let duplicate = await Self.baseline(coordinator, admission: admission) { _ in
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
            await Self.baseline(coordinator, admission: admission) { _ in
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
        #expect(receiptState.withLockedValue { $0 } == [true, true])
    }

    // Interface-capability baseline only: production has no caller identity/receipt API yet.
    // Task 13 must remove this adapter and invoke real execute(admission:...) directly.
    private static func baseline(_ coordinator: MCPReadCoordinator, admission: MCPReadAdmission,
                                 worker: @escaping @Sendable (MCPReadOperation) async -> PreparedReadResult)
        async -> Data {
        _ = admission
        return await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8), worker: worker)
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
