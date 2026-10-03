#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor
struct MCPTaskQuerySnapshotStoreTests {
    @Test func replayExpiryAndCapacity() throws {
        var now = ContinuousClock.now
        let store = MCPTaskQuerySnapshotStore(now: { now }, maxSnapshots: 1, maxBytes: 100)
        let token = UUID().uuidString
        let deadline = now.advanced(by: .seconds(300))
        try store.publish(pages: ["first", "second"], cursors: [token], deadline: deadline)
        #expect(try store.page(for: token) == "second")
        #expect(try store.page(for: token) == "second")
        #expect(throws: (any Error).self) {
            try store.publish(pages: ["a", "b"], cursors: [UUID().uuidString], deadline: deadline)
        }
        #expect(try store.page(for: token) == "second")
        #expect(store.retainedBytes == 11)
        now = deadline
        #expect(throws: (any Error).self) { try store.page(for: token) }
        #expect(store.retainedBytes == 0)
    }

    @Test func atomicPublicationAndClear() throws {
        let now = ContinuousClock.now
        let store = MCPTaskQuerySnapshotStore(now: { now }, maxBytes: 3)
        #expect(throws: (any Error).self) {
            try store.publish(pages: ["1234"], cursors: [], deadline: now.advanced(by: .seconds(300)))
        }
        #expect(store.retainedBytes == 0)
        #expect(throws: (any Error).self) {
            try store.publish(pages: ["a", "b"], cursors: [UUID().uuidString], deadline: now)
        }
        let token = UUID().uuidString
        try store.publish(pages: ["a", "b"], cursors: [token], deadline: now.advanced(by: .seconds(300)))
        store.clear()
        #expect(store.retainedBytes == 0)
        #expect(throws: (any Error).self) { try store.page(for: token) }
    }

    @Test func staleListenerExitPreservesPagesButCurrentExitInvalidatesThem() throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        let token = UUID().uuidString
        try env.handler.taskQuerySnapshots.publish(
            pages: ["first", "second"], cursors: [token],
            deadline: ContinuousClock.now.advanced(by: .seconds(300))
        )
        server.listenerDidExit(generation: -1, failure: "stale")
        #expect(try env.handler.taskQuerySnapshots.page(for: token) == "second")
        #expect(env.handler.taskQueryAdmissionOpen)
        server.listenerDidExit(generation: 0, failure: "bind or listener failure")
        #expect(throws: (any Error).self) { try env.handler.taskQuerySnapshots.page(for: token) }
        #expect(!env.handler.taskQueryAdmissionOpen)
        #expect(server.startError == "bind or listener failure")
    }

}
#endif
