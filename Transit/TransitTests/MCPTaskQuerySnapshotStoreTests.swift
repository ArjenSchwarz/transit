#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
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

    @Test func frozenMetadataAndCursorFamilySurviveExpiry() throws {
        var now = ContinuousClock.now
        let store = MCPTaskQuerySnapshotStore(now: { now })
        let token = UUID().uuidString
        let reusable = "00000000-0000-8000-8000-000000000001"
        let metadata = Data("original metadata bytes".utf8)
        let deadline = now + .seconds(300)
        let reservation = try #require(try store.prepare(pages: ["first", "second"], cursors: [token],
            deadline: deadline, operationID: UUID(), metadataBytes: metadata, policy: .cached))
        #expect(throws: (any Error).self) { try store.page(for: token) }
        store.domain.withLock { reservation.commitLocked(in: store.domain) }
        #expect(try store.retainedPage(for: token).metadataBytes == metadata)
        #expect(try store.retainedPage(for: token).policy == .cached)
        now = deadline
        #expect(throws: (any Error).self) { try store.page(for: token) }
        #expect(MCPCursorFamily.classify(token) == .ordinary)
        #expect(MCPCursorFamily.classify(reusable) == .reusable)
        #expect(store.retainedBytes == 0)
    }

    @Test func wholeBatchPublishesBothOrdinaryCreatesOnlyAfterAssembly() async throws {
        let domain = MCPReadPublicationDomain()
        let coordinator = MCPReadCoordinator(domain: domain)
        let store = MCPTaskQuerySnapshotStore(domain: domain)
        let tokens = [UUID().uuidString, UUID().uuidString]
        let deadline = ContinuousClock.now + .seconds(300)
        let first = try #require(try store.prepare(pages: ["first", "a"], cursors: [tokens[0]],
                                              deadline: deadline, operationID: UUID()))
        let second = try #require(try store.prepare(pages: ["second", "b"], cursors: [tokens[1]],
                                               deadline: deadline, operationID: UUID()))
        let errors = PreencodedPublicationErrors(busy: Data("busy".utf8), expired: Data("expired".utf8),
                                                  capacity: Data("capacity".utf8))
        let elements = [first, second].map { reservation in
            MCPReadBatchElement.read(MCPReadBatchWork(timeout: Data("timeout".utf8), busy: Data("busy".utf8),
                responds: true) { _ in
                PreparedReadResult(encodedResponse: Data("success".utf8), publications: [reservation],
                                   publicationErrors: errors)
            })
        }
        let bytes = await coordinator.executeBatch(elements) { results in
            #expect(try domain.accounting(for: store.publicationStoreID).visibleBytes == 0)
            let aggregate = try store.prepareAggregate(results.compactMap { $0 }.flatMap(\.publications), in: domain)
            #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 13)
            return PreparedReadResult(encodedResponse: Data("[success:a,success:b]".utf8), publications: [aggregate],
                                      publicationErrors: errors)
        }
        #expect(bytes == Data("[success:a,success:b]".utf8))
        #expect(try store.page(for: tokens[0]) == "a")
        #expect(try store.page(for: tokens[1]) == "b")
        #expect(try domain.snapshot(for: store.publicationStoreID).version == 1)
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
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
