#if os(macOS)
import Foundation
import Testing
@testable import Transit

extension MCPReusableSnapshotStoreTests {
    func result(_ publication: any MCPPreparedPublication, id: String) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: Data("success:".appending(id).utf8), publications: [publication],
            publicationErrors: PreencodedPublicationErrors(busy: Data("READ_BUSY".utf8),
                expired: Data("INVALID_SNAPSHOT".utf8), capacity: Data("QUERY_CAPACITY_EXCEEDED".utf8)))
    }

    @Test func allStoresValidateBeforeAnyCommitAndRejectedBytesContainNoIDs() async throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let firstStore = try MCPReusableSnapshotStore(domain: domain)
        let secondStore = try MCPReusableSnapshotStore(domain: domain)
        let first = try bundle(capture)
        let second = try bundle(capture)
        let left = try stage(first, store: firstStore)
        let right = try stage(second, store: secondStore)
        try secondStore.invalidate()
        let coordinator = MCPReadCoordinator(domain: domain)
        let prepared = PreparedReadResult(encodedResponse: Data("success:first,second".utf8),
            publications: [left, right], publicationErrors: PreencodedPublicationErrors(
                busy: Data("READ_BUSY".utf8), expired: Data("INVALID_SNAPSHOT".utf8),
                capacity: Data("QUERY_CAPACITY_EXCEEDED".utf8)))
        let response = await coordinator.execute(timeout: Data("READ_TIMEOUT".utf8),
            busy: Data("READ_BUSY".utf8)) { _ in
            prepared
        }
        #expect(response == Data("READ_BUSY".utf8))
        #expect(try #require(String(bytes: response, encoding: .utf8))
            .contains(first.root.capture.metadata.snapshotId) == false)
        #expect(try #require(String(bytes: response, encoding: .utf8))
            .contains(second.root.capture.metadata.snapshotId) == false)
        for store in [firstStore, secondStore] {
            #expect(try domain.accounting(for: store.publicationStoreID).visibleEntries == 0)
            #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
        }
    }

    @Test func lateEncodedSuccessAfterTimeoutCannotPublishRoot() async throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        let publication = try stage(candidate, store: store)
        let prepared = result(publication, id: candidate.root.capture.metadata.snapshotId)
        let coordinator = MCPReadCoordinator(domain: domain, cutoff: .milliseconds(20))
        let response = await coordinator.execute(timeout: Data("READ_TIMEOUT".utf8),
            busy: Data("READ_BUSY".utf8)) { _ in
            try? await Task.sleep(for: .milliseconds(80))
            return prepared
        }
        #expect(response == Data("READ_TIMEOUT".utf8))
        // Physical completion follows coordinator.offer and its reservation cleanup.
        // Poll cooperatively so this async test never blocks an executor with a semaphore.
        for _ in 0..<1_000 {
            if coordinator.unfinishedCount == 0 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(coordinator.unfinishedCount == 0)
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
        #expect(try domain.accounting(for: store.publicationStoreID).visibleEntries == 0)
        #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
            try store.view(for: candidate.root.capture.metadata.snapshotId, now: capture.createdAt)
        }
    }

    @Test func encodingFailureRollsBackPrivateReservationWithoutLeakingIDs() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        let reservation = try store.reserveCreate(bundle: candidate, publicationDeadline: capture.retentionDeadline)
        // Handler-side encoding abort owns rollback, before any prepared success enters the gate.
        try store.rollback(reservation)
        let failureBytes = Data("serialization_failure".utf8)
        #expect(try #require(String(bytes: failureBytes, encoding: .utf8))
            .contains(candidate.root.capture.metadata.snapshotId) == false)
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
        #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
            try store.view(for: candidate.root.capture.metadata.snapshotId, now: capture.createdAt)
        }
    }

    @Test func admissionDeadlineIsIndependentOfRootLifetime() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        let deadline = capture.createdAt + .milliseconds(4_850)
        let publication = try stage(candidate, store: store, deadline: deadline)
        domain.setTestingInstant(deadline)
        #expect(domain.withLock { publication.validateLocked(in: domain) } == .expired)
        domain.withLock { publication.discardLocked(in: domain) }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
        #expect(capture.retentionDeadline > deadline)
    }

    @Test func concurrentExpiryAndLifecycleInvalidationCannotPublishPendingAppend() async throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        try commit(stage(candidate, store: store), in: domain)
        let cursor = cursorToken()
        let reservation = try store.reserveAppend(snapshotID: candidate.root.capture.metadata.snapshotId,
            pages: [Data([1])], cursors: [cursor], publicationDeadline: capture.retentionDeadline + .seconds(1))
        let publication = try store.prepare(reservation: reservation)
        let expiry = Task.detached { domain.setTestingInstant(capture.retentionDeadline) }
        let restart = Task.detached { try store.invalidate() }
        await expiry.value
        try await restart.value
        #expect(domain.withLock { publication.validateLocked(in: domain) } != nil)
        domain.withLock { publication.discardLocked(in: domain) }
        #expect(throws: MCPReusableSnapshotError.invalidCursor) {
            try store.page(for: cursor, now: capture.retentionDeadline)
        }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
    }

    private func probedBundle(_ capture: CapturedReadView, domain: MCPReadPublicationDomain,
                              outcome: MCPStoreLifetimeOutcome) throws -> EncodedViewBundle {
        let base = try bundle(capture)
        return EncodedViewBundle(root: base.root, pages: base.pages, cursors: base.cursors,
            encodedCaptureByteCount: base.encodedCaptureByteCount,
            lifetimeProbe: MCPStoreLifetimeProbe(domain: domain, outcome: outcome))
    }

    @Test func discardedBundleLastReferenceIsReleasedAfterUnlock() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let outcome = MCPStoreLifetimeOutcome()
        var publication: (any MCPPreparedPublication)? = try stage(
            probedBundle(capture, domain: domain, outcome: outcome), store: store)
        domain.withLock {
            publication?.discardLocked(in: domain)
            publication = nil
        }
        #expect(outcome.released.wait(timeout: .now() + 2) == .success)
        #expect(outcome.reenteredWithoutBlocking)
    }

    @Test func invalidatedBundleLastReferenceIsReleasedAfterUnlock() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let outcome = MCPStoreLifetimeOutcome()
        var publication: (any MCPPreparedPublication)? = try stage(
            probedBundle(capture, domain: domain, outcome: outcome), store: store)
        try commit(try #require(publication), in: domain)
        publication = nil
        try store.invalidate()
        #expect(outcome.released.wait(timeout: .now() + 2) == .success)
        #expect(outcome.reenteredWithoutBlocking)
    }
}

nonisolated private final class MCPStoreLifetimeOutcome: @unchecked Sendable {
    let released = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var reentered = false
    var reenteredWithoutBlocking: Bool { lock.withLock { reentered } }
    func record(_ value: Bool) { lock.withLock { reentered = value }; released.signal() }
}

nonisolated private final class MCPStoreLifetimeProbe: MCPReusableSnapshotLifetimeProbe {
    let domain: MCPReadPublicationDomain
    let outcome: MCPStoreLifetimeOutcome
    init(domain: MCPReadPublicationDomain, outcome: MCPStoreLifetimeOutcome) {
        self.domain = domain
        self.outcome = outcome
    }
    deinit {
        let reentered = DispatchSemaphore(value: 0)
        let domain = domain
        DispatchQueue.global().async { _ = domain.withLock { reentered.signal() } }
        // A release under the domain lock blocks the other queue until deinit returns.
        outcome.record(reentered.wait(timeout: .now() + .milliseconds(250)) == .success)
    }
}

#endif
