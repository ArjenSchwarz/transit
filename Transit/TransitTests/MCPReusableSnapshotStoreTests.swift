#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Behavior-first coverage. Until task 7, operational scaffold throws are test failures,
/// not expected outcomes. Clock advances never sleep or extend the original capture.
@MainActor @Suite(.serialized)
struct MCPReusableSnapshotStoreTests {
    private let maxBytes = 16 * 1024 * 1024

    func cursorToken() -> String { "00000000-0000-8000-8000-" + UUID().uuidString.suffix(12) }

    func bundle(_ capture: CapturedReadView, id: String = UUID().uuidString,
                captureBytes: Int = 100, pages: [Data] = [], cursors: [String] = []) throws -> EncodedViewBundle {
        let metadata = ReadCaptureMetadata(asOf: capture.metadata.asOf, snapshotId: id,
                                          freshness: capture.metadata.freshness, read: capture.metadata.read)
        let copied = CapturedReadView(completeness: capture.completeness, captureScope: capture.captureScope,
            metadata: metadata, createdAt: capture.createdAt, retentionDeadline: capture.retentionDeadline,
            projects: capture.projects, tasks: capture.tasks, milestones: capture.milestones,
            comments: capture.comments)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let root = RetainedView(capture: copied, frozenMetadataBytes: try encoder.encode(metadata),
            window: MCPPortfolioFixture.window,
            initialRequest: .initial(window: MCPPortfolioFixture.window, limit: 1, project: nil, policy: .cached),
            firstPage: Data("original first page".utf8))
        return EncodedViewBundle(root: root, pages: pages, cursors: cursors,
                                 encodedCaptureByteCount: captureBytes)
    }

    func stage(_ bundle: EncodedViewBundle, store: MCPReusableSnapshotStore,
               deadline: ContinuousClock.Instant? = nil) throws -> any MCPPreparedPublication {
        let reservation = try store.reserveCreate(bundle: bundle,
            publicationDeadline: deadline ?? bundle.root.capture.retentionDeadline)
        return try store.prepare(reservation: reservation)
    }

    func commit(_ publication: any MCPPreparedPublication, in domain: MCPReadPublicationDomain) throws {
        try domain.withLock {
            if let rejection = publication.validateLocked(in: domain) { throw rejection }
            publication.commitLocked(in: domain)
        }
    }

    func metadataBytes(_ root: RetainedView) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(root.capture.metadata)
    }

    @Test func privateReservationPublishesOnlyAtGateAndPreservesCapture() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        let publication = try stage(candidate, store: store)
        #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
            try store.view(for: candidate.root.capture.metadata.snapshotId, now: capture.createdAt)
        }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingEntries == 1)
        try commit(publication, in: domain)
        let root = try store.retainedView(for: candidate.root.capture.metadata.snapshotId, now: capture.createdAt)
        #expect(try metadataBytes(root) == metadataBytes(candidate.root))
        #expect(root.capture.retentionDeadline == capture.retentionDeadline)
        #expect(root.capture.captureScope == capture.captureScope)
        #expect(root.capture.tasks.map(\.revision) == capture.tasks.map(\.revision))
        #expect(root.capture.tasks.map(\.fullRecordWithoutCommentsJSON)
            == capture.tasks.map(\.fullRecordWithoutCommentsJSON))
        #expect(root.frozenMetadataBytes == candidate.root.frozenMetadataBytes)
        #expect(root.firstPage == candidate.root.firstPage)
        #expect(root.window.start == candidate.root.window.start && root.window.end == candidate.root.window.end)
        guard case .initial(_, let limit, _, let policy) = root.initialRequest else {
            Issue.record("Stored initial summary request changed branch")
            return
        }
        #expect(limit == 1 && policy == .cached)
    }

    @Test func eightViewsAreRetainedWithoutEvictionAndNinthFails() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        var ids: [String] = []
        for _ in 0..<8 {
            let candidate = try bundle(capture)
            try commit(stage(candidate, store: store), in: domain)
            ids.append(candidate.root.capture.metadata.snapshotId)
        }
        #expect(throws: PublicationRejection.capacity) { try stage(bundle(capture), store: store) }
        for id in ids { #expect(try store.view(for: id, now: capture.createdAt).metadata.snapshotId == id) }
        #expect(try domain.accounting(for: store.publicationStoreID).visibleEntries == 8)
    }

    @Test func pendingReservationsConsumeCapacityAndRollbackExactlyOnce() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture, captureBytes: maxBytes - 32)
        let reservation = try store.reserveCreate(bundle: candidate, publicationDeadline: capture.retentionDeadline)
        // First summary page is charged in addition to encoded capture, even without cursors.
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes
            == candidate.encodedCaptureByteCount + candidate.root.firstPage.count)
        #expect(throws: PublicationRejection.capacity) { try stage(bundle(capture, captureBytes: 33), store: store) }
        try store.rollback(reservation)
        try store.rollback(reservation)
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
        #expect(try domain.accounting(for: store.publicationStoreID).visibleEntries == 0)
    }

    @Test func captureFirstPageAndAllContinuationBytesShareSixteenMiBLimit() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let page = Data(repeating: 7, count: 80)
        let firstPageBytes = Data("original first page".utf8).count
        let candidate = try bundle(capture, captureBytes: maxBytes - firstPageBytes - page.count,
                               pages: [page], cursors: [cursorToken()])
        try commit(stage(candidate, store: store), in: domain)
        #expect(try domain.accounting(for: store.publicationStoreID).visibleBytes == maxBytes)
        #expect(throws: PublicationRejection.capacity) {
            try store.reserveAppend(snapshotID: candidate.root.capture.metadata.snapshotId,
                pages: [Data([1])], cursors: [cursorToken()], publicationDeadline: capture.retentionDeadline)
        }
    }

    @Test func appendChargesOnlyNewPagesAndReplaysFrozenRoot() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        try commit(stage(candidate, store: store), in: domain)
        let initial = try domain.accounting(for: store.publicationStoreID)
        let cursor = cursorToken()
        let bytes = Data("frozen task page".utf8)
        let reservation = try store.reserveAppend(snapshotID: candidate.root.capture.metadata.snapshotId,
            pages: [bytes], cursors: [cursor], publicationDeadline: capture.retentionDeadline)
        let pending = try domain.accounting(for: store.publicationStoreID)
        #expect(pending.pendingEntries == 0 && pending.pendingBytes == bytes.count)
        try commit(store.prepare(reservation: reservation), in: domain)
        #expect(try domain.accounting(for: store.publicationStoreID).visibleBytes == initial.visibleBytes + bytes.count)
        let page = try store.page(for: cursor, now: capture.createdAt + .seconds(200))
        #expect(page.encodedPage == bytes)
        #expect(try metadataBytes(page.root) == metadataBytes(candidate.root))
        #expect(page.root.capture.retentionDeadline == capture.retentionDeadline)
    }

    @Test func originalFiveMinuteBoundaryExpiresRootAndPagesTogether() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        #expect(capture.createdAt.duration(to: capture.retentionDeadline) == .seconds(300))
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let cursor = cursorToken()
        let candidate = try bundle(capture, pages: [Data([1])], cursors: [cursor])
        try commit(stage(candidate, store: store), in: domain)
        let before = capture.retentionDeadline - .nanoseconds(1)
        #expect(try store.page(for: cursor, now: before).root.capture.retentionDeadline == capture.retentionDeadline)
        domain.setTestingInstant(capture.retentionDeadline)
        #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
            try store.view(for: candidate.root.capture.metadata.snapshotId, now: capture.retentionDeadline)
        }
        #expect(throws: MCPReusableSnapshotError.invalidCursor) {
            try store.page(for: cursor, now: capture.retentionDeadline)
        }
        #expect(try domain.accounting(for: store.publicationStoreID).visibleBytes == 0)
    }

}

extension MCPReusableSnapshotStoreTests {
    @Test func aggregateTwoCreatesUsesOneSwapAndPreservesBoth() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let first = try bundle(capture)
        let second = try bundle(capture)
        let version = try domain.snapshot(for: store.publicationStoreID).version
        let left = try stage(first, store: store)
        let right = try stage(second, store: store)
        let aggregate = try store.prepareAggregate([left, right], in: domain)
        #expect(try domain.accounting(for: store.publicationStoreID).pendingEntries == 2)
        domain.withLock { left.discardLocked(in: domain); right.discardLocked(in: domain) }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingEntries == 2)
        try commit(aggregate, in: domain)
        #expect(try domain.snapshot(for: store.publicationStoreID).version == version + 1)
        for candidate in [first, second] {
            #expect(try store.view(for: candidate.root.capture.metadata.snapshotId,
                now: capture.createdAt).tasks.count == 9)
        }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
    }

    @Test func aggregateTwoAppendsRetainsBothWithoutReplacingOriginal() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        try commit(stage(candidate, store: store), in: domain)
        let cursors = [cursorToken(), cursorToken()]
        let pages = [Data([1, 2]), Data([3, 4, 5])]
        var publications: [any MCPPreparedPublication] = []
        for index in 0..<2 {
            let reservation = try store.reserveAppend(snapshotID: candidate.root.capture.metadata.snapshotId,
                pages: [pages[index]], cursors: [cursors[index]], publicationDeadline: capture.retentionDeadline)
            publications.append(try store.prepare(reservation: reservation))
        }
        let version = try domain.snapshot(for: store.publicationStoreID).version
        try commit(store.prepareAggregate(publications, in: domain), in: domain)
        #expect(try domain.snapshot(for: store.publicationStoreID).version == version + 1)
        for index in 0..<2 {
            #expect(try store.page(for: cursors[index], now: capture.createdAt).encodedPage == pages[index])
        }
    }

    @Test func staleCandidateCannotOverwriteConcurrentPublication() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let winner = try bundle(capture)
        let loser = try bundle(capture)
        let first = try stage(winner, store: store)
        let stale = try stage(loser, store: store)
        try commit(first, in: domain)
        #expect(domain.withLock { stale.validateLocked(in: domain) } == .busy)
        domain.withLock { stale.discardLocked(in: domain); stale.discardLocked(in: domain) }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingEntries == 0)
        #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
            try store.view(for: loser.root.capture.metadata.snapshotId, now: capture.createdAt)
        }
        #expect(try store.view(for: winner.root.capture.metadata.snapshotId, now: capture.createdAt).tasks.count == 9)
    }

    @Test func lifecycleInvalidatesPublishedRootAndPendingAppend() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        try commit(stage(candidate, store: store), in: domain)
        let cursor = cursorToken()
        let append = try store.reserveAppend(snapshotID: candidate.root.capture.metadata.snapshotId,
            pages: [Data([1])], cursors: [cursor], publicationDeadline: capture.retentionDeadline)
        let publication = try store.prepare(reservation: append)
        try store.invalidate()
        #expect(domain.withLock { publication.validateLocked(in: domain) } != nil)
        domain.withLock { publication.discardLocked(in: domain) }
        #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
            try store.view(for: candidate.root.capture.metadata.snapshotId, now: capture.createdAt)
        }
        #expect(throws: MCPReusableSnapshotError.invalidCursor) { try store.page(for: cursor, now: capture.createdAt) }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
    }

    @Test func expiryDuringPreparedAppendRejectsWithoutExtendingRoot() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        try commit(stage(candidate, store: store), in: domain)
        let reservation = try store.reserveAppend(snapshotID: candidate.root.capture.metadata.snapshotId,
            pages: [Data([1])], cursors: [cursorToken()],
            publicationDeadline: capture.retentionDeadline + .seconds(10))
        let publication = try store.prepare(reservation: reservation)
        domain.setTestingInstant(capture.retentionDeadline)
        #expect(domain.withLock { publication.validateLocked(in: domain) } == .expired)
        domain.withLock { publication.discardLocked(in: domain) }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
    }

    @Test func cursorTokensCannotCollideAcrossStores() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let first = try MCPReusableSnapshotStore(domain: domain)
        let second = try MCPReusableSnapshotStore(domain: domain)
        let cursor = cursorToken()
        let publication = try stage(bundle(capture, pages: [Data([1])], cursors: [cursor]), store: first)
        #expect(throws: PublicationRejection.busy) {
            try stage(bundle(capture, pages: [Data([2])], cursors: [cursor]), store: second)
        }
        domain.withLock { publication.discardLocked(in: domain) }
        #expect(try domain.accounting(for: second.publicationStoreID).pendingEntries == 0)
    }

    @Test func reservedAndPublishedCursorCollisionsAreRejected() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let cursor = "00000000-0000-8000-8000-000000000001"
        let first = try stage(bundle(capture, pages: [Data([1])], cursors: [cursor]), store: store)
        #expect(throws: PublicationRejection.busy) {
            try stage(bundle(capture, pages: [Data([2])], cursors: [cursor]), store: store)
        }
        try commit(first, in: domain)
        #expect(throws: PublicationRejection.busy) {
            try stage(bundle(capture, pages: [Data([3])], cursors: [cursor]), store: store)
        }
    }

    @Test func malformedPagePairsAndSelectedQueryAreRejectedWithoutReservation() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        #expect(throws: MCPReusableSnapshotError.incompatible) {
            try stage(bundle(capture, pages: [Data([1])], cursors: []), store: store)
        }
        let selected = CapturedReadView(completeness: .completePortfolio, captureScope: .selectedQuery,
            metadata: capture.metadata, createdAt: capture.createdAt, retentionDeadline: capture.retentionDeadline,
            projects: capture.projects, tasks: capture.tasks, milestones: capture.milestones,
            comments: capture.comments)
        #expect(throws: MCPReusableSnapshotError.incompatible) { try stage(bundle(selected), store: store) }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingEntries == 0)
    }

    @Test func scopedViewDoesNotTurnIdentityClosureIntoPortfolioScope() throws {
        let fixture = try MCPPortfolioSavedFixture()
        let capture = try MCPReadCaptureBuilder(container: fixture.owner.container, fence: .actorOnlyTestFixture)
            .capture(ReadCaptureRequest(projectSelectors: [.id(MCPPortfolioFixture.populatedProjectID)],
                selection: .portfolio, completeness: .completePortfolio, includeComments: false))
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        try commit(stage(candidate, store: store), in: domain)
        let retained = try store.view(for: candidate.root.capture.metadata.snapshotId, now: capture.createdAt)
        #expect(retained.captureScope == capture.captureScope)
        guard case .projects(let keys) = retained.captureScope else {
            Issue.record("Scoped retained view widened to portfolio")
            return
        }
        #expect(keys.count == 1)
    }
}

#endif
