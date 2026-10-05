#if os(macOS)
import Foundation
import Testing
@testable import Transit

@Suite(.serialized)
nonisolated struct TaskConsolidationReadLifecycleTests {
    @Test @concurrent func listenerStopDoesNotCancelNativeOrReopenOldListener() async throws {
        let coordinator = MCPReadCoordinator(cutoff: .seconds(1))
        let listener = UUID(), replacement = UUID(), latch = ConsolidationReadLatch()
        coordinator.startListener(listener)
        let native = Task { await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
            admission: MCPReadAdmission(owner: .native)) { _ in
                await latch.wait()
                return Self.result("native")
            } }
        let stopped = Task { await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
            admission: MCPReadAdmission(owner: .listener(listener))) { _ in
                await latch.wait()
                return Self.result("late listener")
            } }
        for _ in 0..<100 where coordinator.unfinishedCount < 2 {
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(coordinator.unfinishedCount == 2)
        coordinator.stopListener(listener)
        #expect(await stopped.value == Data("timeout".utf8))
        #expect(coordinator.unfinishedCount == 2)
        coordinator.startListener(replacement)
        let old = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
            admission: MCPReadAdmission(owner: .listener(listener))) { _ in
                Issue.record("retired listener dispatched a worker")
                return Self.result("old")
            }
        #expect(old == Data("busy".utf8))
        await latch.release()
        #expect(await native.value == Data("native".utf8))
        await Self.drain(coordinator)
        #expect(coordinator.unfinishedCount == 0)
    }

    @Test @concurrent func cancelledNativeAndListenerReadsShareEightPhysicalSlots() async throws {
        let coordinator = MCPReadCoordinator(cutoff: .milliseconds(50))
        let listener = UUID(), latch = ConsolidationReadLatch()
        coordinator.startListener(listener)
        let calls = (0..<8).map { index in Task {
            await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
                admission: MCPReadAdmission(owner: index.isMultiple(of: 2) ? .native : .listener(listener))) { _ in
                    await latch.wait()
                    return Self.result("late")
                }
        } }
        for call in calls { #expect(await call.value == Data("timeout".utf8)) }
        #expect(coordinator.unfinishedCount == 8)
        coordinator.stopListener(listener)
        coordinator.startListener(UUID())
        #expect(await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
            admission: MCPReadAdmission(owner: .native)) { _ in Self.result("wrong") } == Data("busy".utf8))
        await latch.release()
        await Self.drain(coordinator)
        #expect(coordinator.unfinishedCount == 0)
    }

    @Test @concurrent func originalAdmissionDeadlineIsNotRestartedForNativeDispatch() async throws {
        let coordinator = MCPReadCoordinator()
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
            admittedAt: .now - .seconds(6), admission: MCPReadAdmission(owner: .native)) { _ in
                Issue.record("expired native read dispatched")
                return Self.result("wrong")
            }
        #expect(bytes == Data("timeout".utf8))
        await Self.drain(coordinator)
        #expect(coordinator.unfinishedCount == 0)
    }

    @Test @concurrent func nativeCodableValuesUseTheSameAdmissionAndPhysicalCompletion() async {
        let coordinator = MCPReadCoordinator()
        let fallback = ConsolidationNativeProbe(available: false, operationIds: [])
        let expected = ConsolidationNativeProbe(available: true, operationIds: [UUID()])
        let value = await coordinator.executeValue(unavailable: fallback) { operation in
            #expect(operation.shouldContinue())
            return expected
        }
        #expect(value == expected)
        await Self.drain(coordinator)
        #expect(coordinator.unfinishedCount == 0)
        coordinator.stop()
        #expect(await coordinator.executeValue(unavailable: fallback) { _ in
            Issue.record("closed admission dispatched native worker")
            return expected
        } == fallback)
    }

    private static func result(_ string: String) -> PreparedReadResult {
        let bytes = Data(string.utf8)
        return PreparedReadResult(encodedResponse: bytes, publications: [],
            publicationErrors: PreencodedPublicationErrors(busy: bytes, expired: bytes, capacity: bytes))
    }

    @concurrent private static func drain(_ coordinator: MCPReadCoordinator) async {
        for _ in 0..<100 where coordinator.unfinishedCount != 0 {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

private nonisolated struct ConsolidationNativeProbe: Codable, Equatable, Sendable {
    let available: Bool
    let operationIds: [UUID]
}

private actor ConsolidationReadLatch {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
#endif
