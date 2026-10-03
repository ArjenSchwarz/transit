#if os(macOS)
import Foundation
import NIOConcurrencyHelpers
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadServerCoordinatorLifecycleTests {
    @Test func actualListenerRestartKeepsCoordinatorAndOldPhysicalWorkers() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let coordinator = env.handler.readCoordinator
        let server = MCPServer(toolHandler: env.handler, readCoordinator: coordinator)
        let listener = MCPServerLifecycleTests()
        let port = try listener.availableLoopbackPort()
        await server.start(port: port)
        guard await listener.waitUntilListening(port: port) else {
            await server.stop()
            Issue.record("Initial actual listener did not start")
            return
        }
        let oldGeneration = server.listenerGeneration
        let gate = LifecycleReadGate()
        let receipts = NIOLockedValueBox<[UUID]>([])
        let calls = startWorkers(coordinator, gate: gate, receipts: receipts)
        let startDeadline = ContinuousClock.now + .seconds(1)
        while await gate.count < 8 && .now < startDeadline { await Task.yield() }
        #expect(await gate.count == 8)
        await server.restart(port: port)
        #expect(await listener.waitUntilListening(port: port))
        for call in calls { #expect(await call.value == Data("timeout".utf8)) }
        #expect(server.readCoordinator === coordinator && env.handler.readCoordinator === coordinator)
        #expect(coordinator.unfinishedCount == 8 && receipts.withLockedValue { $0 }.isEmpty)
        server.listenerDidExit(generation: oldGeneration, failure: "old listener completion")
        #expect(server.isRunning && env.handler.taskQueryAdmissionOpen && server.startError == nil)
        let ninth = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { _ in
            Issue.record("Replacement listener forgot old physical permits")
            return Self.result("unexpected")
        }
        #expect(ninth == Data("busy".utf8))
        await gate.release()
        let drainDeadline = ContinuousClock.now + .seconds(1)
        while (coordinator.unfinishedCount != 0 || receipts.withLockedValue({ $0.count }) != 8)
            && .now < drainDeadline { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0)
        #expect(Set(receipts.withLockedValue { $0 }).count == 8)
        #expect(receipts.withLockedValue { $0.count } == 8)
        let current = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { _ in
            Self.result("current")
        }
        #expect(current == Data("current".utf8))
        await server.stop()
        let finalDeadline = ContinuousClock.now + .seconds(1)
        while coordinator.unfinishedCount != 0 && .now < finalDeadline { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0)
    }

    private func startWorkers(_ coordinator: MCPReadCoordinator, gate: LifecycleReadGate,
                              receipts: NIOLockedValueBox<[UUID]>) -> [Task<Data, Never>] {
        (0..<8).map { _ in
            let id = UUID()
            let admission = MCPReadAdmission(operationID: id, physicalCompletion: {
                receipts.withLockedValue { $0.append(id) }
            })
            return Task {
                await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
                                          admission: admission) { _ in
                    await gate.wait()
                    return Self.result("late")
                }
            }
        }
    }

    nonisolated private static func result(_ value: String) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: Data(value.utf8), publications: [],
                          publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
    }
}

private actor LifecycleReadGate {
    private(set) var count = 0
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        count += 1
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
