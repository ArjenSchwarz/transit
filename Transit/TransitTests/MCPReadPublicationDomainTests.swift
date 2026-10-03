#if os(macOS)
import Foundation
import Testing
@testable import Transit

@Suite(.serialized)
nonisolated struct MCPReadPublicationDomainTests {
    private let deadline = ContinuousClock.now + .seconds(300)

    private func index(_ roots: [MCPPublicationRoot] = []) throws -> PublicationTestIndex {
        PublicationTestIndex(descriptor: try MCPPublicationIndexDescriptor(roots: roots))
    }

    private func reserve(_ domain: MCPReadPublicationDomain, _ store: MCPPublicationStoreID,
                         _ candidate: PublicationTestIndex, entries: Int, bytes: Int,
                         tokens: Set<String>) throws -> MCPPublicationReservation {
        let base = try domain.snapshot(for: store)
        return try domain.reserve(storeID: store, operationID: UUID(), expectedVersion: base.version,
                                  expectedTokenVersion: base.tokenVersion, index: candidate,
                                  chargeEntries: entries, chargeBytes: bytes, newTokens: tokens,
                                  deadline: deadline)
    }

    @Test func capacityTransferAndExactlyOnceRollback() throws {
        let domain = MCPReadPublicationDomain()
        let store = MCPPublicationStoreID(rawValue: UUID())
        try domain.register(storeID: store, index: index(), maxEntries: 2, maxBytes: 10)
        let rootA = MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 4, tokens: ["a"])
        let rootB = MCPPublicationRoot(id: "b", deadline: deadline, encodedByteCount: 6, tokens: ["b"])
        let first = try reserve(domain, store, index([rootA]), entries: 1, bytes: 4, tokens: ["a"])
        let second = try reserve(domain, store, index([rootB]), entries: 1, bytes: 6, tokens: ["b"])
        #expect(try domain.accounting(for: store) == MCPPublicationAccounting(visibleEntries: 0, visibleBytes: 0,
                                                                          pendingEntries: 2, pendingBytes: 10))
        #expect(throws: PublicationRejection.capacity) {
            try reserve(domain, store, index([MCPPublicationRoot(id: "c", deadline: deadline,
                                                                 encodedByteCount: 1, tokens: ["c"])]),
                        entries: 1, bytes: 1, tokens: ["c"])
        }
        let unrelated = MCPPublicationStoreID(rawValue: UUID())
        try domain.register(storeID: unrelated, index: index(), maxEntries: 8, maxBytes: 100)
        let other = try reserve(domain, unrelated, index([MCPPublicationRoot(id: "x", deadline: deadline,
                                                                            encodedByteCount: 1, tokens: ["x"])]),
                                entries: 1, bytes: 1, tokens: ["x"])
        let aggregate = try domain.transfer([first, second], aggregateIndex: index([rootA, rootB]), operationID: UUID())
        #expect(try domain.accounting(for: store).pendingBytes == 10)
        domain.withLock { first.discardLocked(in: domain); second.discardLocked(in: domain) }
        #expect(try domain.accounting(for: store).pendingBytes == 10)
        domain.withLock { aggregate.discardLocked(in: domain); aggregate.discardLocked(in: domain) }
        #expect(try domain.accounting(for: store).pendingBytes == 0)
        domain.withLock { other.discardLocked(in: domain) }
    }

    @Test func staleCASAndGlobalTokenCollisions() throws {
        let domain = MCPReadPublicationDomain()
        let store = MCPPublicationStoreID(rawValue: UUID())
        try domain.register(storeID: store, index: index(), maxEntries: 8, maxBytes: 100)
        let root = MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 3, tokens: ["token"])
        let candidate = try reserve(domain, store, index([root]), entries: 1, bytes: 3, tokens: ["token"])
        #expect(throws: PublicationRejection.busy) {
            try reserve(domain, store, index([root]), entries: 1, bytes: 3, tokens: ["token"])
        }
        let sibling = try reserve(domain, store, index([MCPPublicationRoot(id: "b", deadline: deadline,
                                                                          encodedByteCount: 4, tokens: ["b"])]),
                                  entries: 1, bytes: 4, tokens: ["b"])
        domain.withLock { candidate.commitLocked(in: domain) }
        #expect(domain.withLock { sibling.validateLocked(in: domain) } == .busy)
        domain.withLock { sibling.discardLocked(in: domain) }
        #expect(try domain.snapshot(for: store).version == 1)
        #expect(try domain.accounting(for: store).visibleBytes == 3)
        #expect(try domain.accounting(for: store).pendingBytes == 0)
    }

    @Test func appendExpiryAndExactNetCharges() throws {
        var now = ContinuousClock.now
        let domain = MCPReadPublicationDomain(now: { now })
        let store = MCPPublicationStoreID(rawValue: UUID())
        let original = MCPPublicationRoot(id: "a", deadline: now + .seconds(1), encodedByteCount: 2, tokens: ["a"])
        try domain.register(storeID: store, index: index([original]), maxEntries: 8, maxBytes: 100)
        let appended = MCPPublicationRoot(id: "a", deadline: original.deadline, encodedByteCount: 5, tokens: ["a", "b"])
        #expect(throws: PublicationRejection.busy) {
            try reserve(domain, store, index([appended]), entries: 0, bytes: 2, tokens: ["b"])
        }
        let pending = try reserve(domain, store, index([appended]), entries: 0, bytes: 3, tokens: ["b"])
        now = original.deadline
        #expect(domain.withLock { pending.validateLocked(in: domain) } == .expired)
        domain.withLock { pending.discardLocked(in: domain) }
        #expect(try domain.accounting(for: store).visibleBytes == 2)
        let extended = MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 5, tokens: ["a", "b"])
        #expect(throws: PublicationRejection.busy) {
            try reserve(domain, store, index([extended]), entries: 0, bytes: 3, tokens: ["b"])
        }
    }

    @Test @concurrent func validatesAllStoresBeforeAnyCommitAndChoosesPreencodedError() async throws {
        let domain = MCPReadPublicationDomain()
        let coordinator = MCPReadCoordinator(domain: domain)
        let firstStore = MCPPublicationStoreID(rawValue: UUID())
        let secondStore = MCPPublicationStoreID(rawValue: UUID())
        try domain.register(storeID: firstStore, index: index(), maxEntries: 8, maxBytes: 100)
        try domain.register(storeID: secondStore, index: index(), maxEntries: 8, maxBytes: 100)
        let first = try reserve(domain, firstStore, index([MCPPublicationRoot(id: "a", deadline: deadline,
                                                                           encodedByteCount: 1, tokens: ["a"])]),
                                entries: 1, bytes: 1, tokens: ["a"])
        let second = try reserve(domain, secondStore, index([MCPPublicationRoot(id: "b", deadline: deadline,
                                                                              encodedByteCount: 1, tokens: ["b"])]),
                                 entries: 1, bytes: 1, tokens: ["b"])
        try domain.retire(storeID: secondStore, expectedVersion: 0, replacementIndex: index())
        let result = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { _ in
            PreparedReadResult(encodedResponse: Data("success:a,b".utf8), publications: [first, second],
                               publicationErrors: PreencodedPublicationErrors(busy: Data("cas".utf8),
                                   expired: Data("expired".utf8), capacity: Data("capacity".utf8)))
        }
        #expect(result == Data("cas".utf8))
        #expect(try domain.accounting(for: firstStore).visibleBytes == 0)
        #expect(try domain.accounting(for: firstStore).pendingBytes == 0)
        #expect(try domain.accounting(for: secondStore).pendingBytes == 0)
    }
}

nonisolated private final class PublicationTestIndex: MCPPublicationIndex {
    let descriptor: MCPPublicationIndexDescriptor
    init(descriptor: MCPPublicationIndexDescriptor) { self.descriptor = descriptor }
}
#endif
