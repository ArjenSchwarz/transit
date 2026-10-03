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

    // swiftlint:disable:next function_parameter_count
    private func reserve(_ domain: MCPReadPublicationDomain, _ store: MCPPublicationStoreID,
                         _ candidate: PublicationTestIndex, entries: Int, bytes: Int,
                         tokens: Set<String>) throws -> MCPPublicationReservation {
        let base = try domain.snapshot(for: store)
        return try domain.reserve(storeID: store, operationID: UUID(), expectedVersion: base.version,
                                  expectedTokenVersion: base.tokenVersion, index: candidate,
                                  chargeEntries: entries, chargeBytes: bytes, newTokens: tokens,
                                  deadline: deadline)
    }

    private func wait(_ semaphore: DispatchSemaphore) -> DispatchTimeoutResult {
        semaphore.wait(timeout: .now() + 2)
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

    @Test func unrelatedStoreAllocationInvalidatesPinnedTokenVersion() throws {
        let domain = MCPReadPublicationDomain()
        let first = MCPPublicationStoreID(rawValue: UUID())
        let second = MCPPublicationStoreID(rawValue: UUID())
        try domain.register(storeID: first, index: index(), maxEntries: 8, maxBytes: 100)
        try domain.register(storeID: second, index: index(), maxEntries: 8, maxBytes: 100)
        let pinned = try domain.snapshot(for: first)
        let root = MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 1, tokens: ["shared"])
        let pending = try reserve(domain, second, index([root]), entries: 1, bytes: 1, tokens: ["shared"])
        #expect(throws: PublicationRejection.busy) {
            try domain.reserve(storeID: first, operationID: UUID(), expectedVersion: pinned.version,
                expectedTokenVersion: pinned.tokenVersion, index: index([root]),
                chargeEntries: 1, chargeBytes: 1, newTokens: ["shared"], deadline: deadline)
        }
        #expect(throws: PublicationRejection.busy) {
            try reserve(domain, first, index([root]), entries: 1, bytes: 1, tokens: ["shared"])
        }
        #expect(try domain.accounting(for: first).pendingBytes == 0)
        domain.withLock { pending.discardLocked(in: domain) }
        #expect(throws: PublicationRejection.busy) {
            try reserve(domain, first, index([root]), entries: -1, bytes: 1, tokens: ["shared"])
        }
    }

    @Test func appendExpiryAndExactNetCharges() throws {
        var now = ContinuousClock.now
        let domain = MCPReadPublicationDomain(testingInstant: now)
        let store = MCPPublicationStoreID(rawValue: UUID())
        let original = MCPPublicationRoot(id: "a", deadline: now + .seconds(1), encodedByteCount: 2, tokens: ["a"])
        try domain.register(storeID: store, index: index([original]), maxEntries: 8, maxBytes: 100)
        let appended = MCPPublicationRoot(id: "a", deadline: original.deadline, encodedByteCount: 5, tokens: ["a", "b"])
        #expect(throws: PublicationRejection.busy) {
            try reserve(domain, store, index([appended]), entries: 0, bytes: 2, tokens: ["b"])
        }
        let shortened = MCPPublicationRoot(id: "a", deadline: original.deadline - .milliseconds(100),
                                           encodedByteCount: 5, tokens: ["a", "b"])
        #expect(throws: PublicationRejection.busy) {
            try reserve(domain, store, index([shortened]), entries: 0, bytes: 3, tokens: ["b"])
        }
        let pending = try reserve(domain, store, index([appended]), entries: 0, bytes: 3, tokens: ["b"])
        now = original.deadline
        domain.setTestingInstant(now)
        #expect(domain.withLock { pending.validateLocked(in: domain) } == .expired)
        domain.withLock { pending.discardLocked(in: domain) }
        #expect(try domain.accounting(for: store).visibleBytes == 2)
        let extended = MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 5, tokens: ["a", "b"])
        #expect(throws: PublicationRejection.busy) {
            try reserve(domain, store, index([extended]), entries: 0, bytes: 3, tokens: ["b"])
        }
    }

    @Test func twoAppendsAndCreateAppendTransferOneSwap() throws {
        for includeCreate in [false, true] {
            let domain = MCPReadPublicationDomain()
            let store = MCPPublicationStoreID(rawValue: UUID())
            let original = MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 2, tokens: ["a"])
            try domain.register(storeID: store, index: index([original]), maxEntries: 8, maxBytes: 100)
            let appended = MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 5, tokens: ["a", "b"])
            let other = includeCreate
                ? MCPPublicationRoot(id: "c", deadline: deadline, encodedByteCount: 4, tokens: ["c"])
                : MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 6, tokens: ["a", "c"])
            let first = try reserve(domain, store, index([appended]), entries: 0, bytes: 3, tokens: ["b"])
            let second = try reserve(domain, store, index(includeCreate ? [original, other] : [other]),
                                     entries: includeCreate ? 1 : 0, bytes: 4, tokens: ["c"])
            let combined = includeCreate ? [appended, other]
                : [MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 9, tokens: ["a", "b", "c"])]
            let aggregate = try domain.transfer([first, second], aggregateIndex: index(combined), operationID: UUID())
            #expect(try domain.accounting(for: store).pendingBytes == 7)
            domain.withLock {
                #expect(aggregate.validateLocked(in: domain) == nil)
                aggregate.commitLocked(in: domain)
                first.discardLocked(in: domain)
                second.discardLocked(in: domain)
                aggregate.discardLocked(in: domain)
            }
            #expect(try domain.accounting(for: store).visibleBytes == 9)
            #expect(try domain.accounting(for: store).pendingBytes == 0)
            #expect(try domain.snapshot(for: store).version == 1)
        }
    }

}

extension MCPReadPublicationDomainTests {
    @Test func descriptorGetterNeverRunsInsideGate() throws {
        let domain = MCPReadPublicationDomain()
        let store = MCPPublicationStoreID(rawValue: UUID())
        try domain.register(storeID: store,
            index: PublicationReentrantIndex(descriptor: try MCPPublicationIndexDescriptor(roots: []), domain: domain),
            maxEntries: 8, maxBytes: 100)
        let root = MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 1, tokens: ["a"])
        let candidate = PublicationReentrantIndex(descriptor: try MCPPublicationIndexDescriptor(roots: [root]),
                                                 domain: domain)
        let snapshot = try domain.snapshot(for: store)
        let pending = try domain.reserve(storeID: store, operationID: UUID(), expectedVersion: snapshot.version,
            expectedTokenVersion: snapshot.tokenVersion, index: candidate,
            chargeEntries: 1, chargeBytes: 1, newTokens: ["a"], deadline: deadline)
        domain.withLock {
            #expect(pending.validateLocked(in: domain) == nil)
            pending.commitLocked(in: domain)
            pending.discardLocked(in: domain)
        }
        #expect(try domain.accounting(for: store).visibleBytes == 1)
        _ = try domain.snapshot(for: store)
        try domain.retire(storeID: store, expectedVersion: 1, replacementIndex: index())
    }

    @Test @concurrent func commitAndDiscardDestructionAllowConcurrentGate() async throws {
        for commit in [false, true] {
            let domain = MCPReadPublicationDomain()
            let store = MCPPublicationStoreID(rawValue: UUID())
            let started = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            if commit {
                try domain.register(storeID: store,
                    index: PublicationDestructionIndex(descriptor: try MCPPublicationIndexDescriptor(roots: []),
                        started: started, release: release), maxEntries: 8, maxBytes: 100)
                _ = try reserve(domain, store,
                    index([MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 1, tokens: ["a"])]),
                    entries: 1, bytes: 1, tokens: ["a"])
            } else {
                try domain.register(storeID: store, index: index(), maxEntries: 8, maxBytes: 100)
                let base = try domain.snapshot(for: store)
                _ = try domain.reserve(storeID: store, operationID: UUID(), expectedVersion: base.version,
                    expectedTokenVersion: base.tokenVersion,
                    index: PublicationDestructionIndex(descriptor: try MCPPublicationIndexDescriptor(roots: [
                        MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 1, tokens: ["a"])]),
                        started: started, release: release),
                    chargeEntries: 1, chargeBytes: 1, newTokens: ["a"], deadline: deadline)
            }
            let finalizer = Task.detached {
                domain.withLock {
                    if let pending = domain.stores[store]?.pending.values.first {
                        if commit { pending.commitLocked(in: domain) } else { pending.discardLocked(in: domain) }
                    }
                }
            }
            #expect(wait(started) == .success)
            let gateStart = ContinuousClock.now
            let gate = Task.detached { domain.withLock { 42 } }
            #expect(await gate.value == 42)
            #expect(gateStart.duration(to: .now) < .seconds(1))
            release.signal()
            await finalizer.value
        }
    }

    @Test @concurrent func responseSelectionPrecedesLargeRetirementCleanup() async throws {
        let domain = MCPReadPublicationDomain()
        let coordinator = MCPReadCoordinator(domain: domain, cutoff: .milliseconds(100))
        let store = MCPPublicationStoreID(rawValue: UUID())
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        try domain.register(storeID: store,
            index: PublicationDestructionIndex(descriptor: try MCPPublicationIndexDescriptor(roots: []),
                started: started, release: release), maxEntries: 8, maxBytes: 100)
        let pending = try reserve(domain, store,
            index([MCPPublicationRoot(id: "a", deadline: deadline, encodedByteCount: 1, tokens: ["a"])]),
            entries: 1, bytes: 1, tokens: ["a"])
        let start = ContinuousClock.now
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { _ in
            PreparedReadResult(encodedResponse: Data("success:a".utf8), publications: [pending],
                publicationErrors: PreencodedPublicationErrors(busy: Data("busy".utf8),
                    expired: Data("expired".utf8), capacity: Data("capacity".utf8)))
        }
        #expect(bytes == Data("success:a".utf8))
        #expect(start.duration(to: .now) < .seconds(1))
        #expect(wait(started) == .success)
        #expect(coordinator.unfinishedCount == 1)
        release.signal()
        for _ in 0..<100 where coordinator.unfinishedCount > 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(coordinator.unfinishedCount == 0)
    }

    @Test @concurrent func largeIndexDestructionAllowsConcurrentGate() async throws {
        let domain = MCPReadPublicationDomain()
        let store = MCPPublicationStoreID(rawValue: UUID())
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        try domain.register(storeID: store,
            index: PublicationDestructionIndex(descriptor: try MCPPublicationIndexDescriptor(roots: []),
                started: started, release: release), maxEntries: 8, maxBytes: 100)
        let empty = try index()
        let retirement = Task.detached {
            try domain.retire(storeID: store, expectedVersion: 0, replacementIndex: empty)
        }
        #expect(wait(started) == .success)
        let gate = Task.detached { domain.withLock { 42 } }
        #expect(await gate.value == 42)
        release.signal()
        try await retirement.value
    }

    @Test @concurrent func seededTerminalRacesDiscardRealReservations() async throws {
        for seed in 0..<24 {
            let domain = MCPReadPublicationDomain()
            let store = MCPPublicationStoreID(rawValue: UUID())
            let coordinator = MCPReadCoordinator(domain: domain, cutoff: .milliseconds(4))
            try domain.register(storeID: store, index: index(), maxEntries: 8, maxBytes: 100)
            let pending = try reserve(domain, store, index([MCPPublicationRoot(id: "a", deadline: deadline,
                                                                             encodedByteCount: 3, tokens: ["a"])]),
                                      entries: 1, bytes: 3, tokens: ["a"])
            let started = DispatchSemaphore(value: 0)
            let work = Task {
                await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { _ in
                    started.signal()
                    try? await Task.sleep(for: .milliseconds(seed % 7))
                    return PreparedReadResult(encodedResponse: Data("success:a".utf8), publications: [pending],
                        publicationErrors: PreencodedPublicationErrors(busy: Data("busy".utf8),
                            expired: Data("expired".utf8), capacity: Data("capacity".utf8)))
                }
            }
            #expect(wait(started) == .success)
            if seed % 3 == 0 { try await Task.sleep(for: .milliseconds(1)); coordinator.stop() }
            if seed % 5 == 0 { work.cancel() }
            let bytes = await work.value
            for _ in 0..<100 where coordinator.unfinishedCount > 0 {
                try await Task.sleep(for: .milliseconds(1))
            }
            let expected = bytes == Data("success:a".utf8) ? 3 : 0
            #expect(try domain.accounting(for: store).visibleBytes == expected)
            #expect(try domain.accounting(for: store).pendingBytes == 0)
            #expect(coordinator.unfinishedCount == 0)
            domain.withLock { pending.discardLocked(in: domain) }
            #expect(try domain.accounting(for: store).pendingBytes == 0)
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
nonisolated private final class PublicationReentrantIndex: MCPPublicationIndex {
    private let value: MCPPublicationIndexDescriptor
    private unowned let domain: MCPReadPublicationDomain
    var descriptor: MCPPublicationIndexDescriptor { domain.withLock { value } }
    init(descriptor: MCPPublicationIndexDescriptor, domain: MCPReadPublicationDomain) {
        value = descriptor
        self.domain = domain
    }
}

nonisolated private final class PublicationDestructionIndex: MCPPublicationIndex {
    let descriptor: MCPPublicationIndexDescriptor
    let payload = Data(repeating: 1, count: 16 * 1024 * 1024)
    let started: DispatchSemaphore
    let release: DispatchSemaphore
    init(descriptor: MCPPublicationIndexDescriptor, started: DispatchSemaphore, release: DispatchSemaphore) {
        self.descriptor = descriptor
        self.started = started
        self.release = release
    }
    deinit { started.signal(); _ = release.wait(timeout: .now() + 2) }
}
#endif
