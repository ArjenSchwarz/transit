#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Focused store publication-guard regressions; these use real retained entries and domain gates.
@MainActor @Suite(.serialized)
struct MCPReusableSnapshotReadPinTests {
    private let fixtures = MCPReusableSnapshotStoreTests()

    private func cursorToken() -> String { fixtures.cursorToken() }

    private func bundle(_ capture: CapturedReadView, pages: [Data] = [], cursors: [String] = [])
        throws -> EncodedViewBundle {
        try fixtures.bundle(capture, pages: pages, cursors: cursors)
    }

    private func stage(_ bundle: EncodedViewBundle, store: MCPReusableSnapshotStore)
        throws -> any MCPPreparedPublication {
        try fixtures.stage(bundle, store: store)
    }

    private func commit(_ publication: any MCPPreparedPublication, in domain: MCPReadPublicationDomain) throws {
        try fixtures.commit(publication, in: domain)
    }

    @Test func readOnlyPinsValidateWithoutReservingOrSwappingStore() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let cursor = cursorToken()
        let candidate = try bundle(capture, pages: [Data([1, 2])], cursors: [cursor])
        try commit(stage(candidate, store: store), in: domain)
        let initialVersion = try domain.snapshot(for: store.publicationStoreID).version
        let initialAccounting = try domain.accounting(for: store.publicationStoreID)
        let root = try store.preparedRetainedView(for: candidate.root.capture.metadata.snapshotId,
                                                 now: capture.createdAt)
        let page = try store.preparedPage(for: cursor, now: capture.createdAt)
        #expect(root.pin.identity == page.pin.identity)
        #expect(page.page.encodedPage == Data([1, 2]))
        let aggregate = try store.prepareAggregate([root.pin, page.pin, root.pin], in: domain)
        let guardOnly = try #require(aggregate as? MCPReusableSnapshotGuardedPublication)
        #expect(guardOnly.pins.count == 1 && guardOnly.mutation == nil)
        try commit(aggregate, in: domain)
        domain.withLock { aggregate.discardLocked(in: domain) }
        #expect(try domain.snapshot(for: store.publicationStoreID).version == initialVersion)
        #expect(try domain.accounting(for: store.publicationStoreID) == initialAccounting)
        #expect(guardOnly.pins[0].deadline == capture.retentionDeadline)
    }

    @Test func preparedReadPinExpiryRejectsEncodedSuccessAtCoordinatorGate() async throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        try commit(stage(candidate, store: store), in: domain)
        let pinned = try store.preparedRetainedView(for: candidate.root.capture.metadata.snapshotId,
                                                   now: capture.createdAt)
        let guardOnly = try store.prepareAggregate([pinned.pin], in: domain)
        let prepared = PreparedReadResult(encodedResponse: candidate.root.firstPage, publications: [guardOnly],
            publicationErrors: PreencodedPublicationErrors(busy: Data("READ_BUSY".utf8),
                expired: Data("INVALID_SNAPSHOT".utf8), capacity: Data("QUERY_CAPACITY_EXCEEDED".utf8)))
        domain.setTestingInstant(capture.retentionDeadline)
        let coordinator = MCPReadCoordinator(domain: domain)
        let response = await coordinator.execute(timeout: Data("READ_TIMEOUT".utf8),
            busy: Data("READ_BUSY".utf8)) { _ in prepared }
        let drainDeadline = ContinuousClock.now + .seconds(1)
        while coordinator.unfinishedCount != 0 && ContinuousClock.now < drainDeadline {
            await Task.yield()
        }
        #expect(coordinator.unfinishedCount == 0)
        #expect(response == Data("INVALID_SNAPSHOT".utf8))
        #expect(domain.withLock { pinned.pin.validateLocked(in: domain) } == .expired)
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
    }

    @Test func sameIDRecreationRejectsOldPinWhileNewRootIsValid() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        let id = candidate.root.capture.metadata.snapshotId
        try commit(stage(candidate, store: store), in: domain)
        let old = try store.preparedRetainedView(for: id, now: capture.createdAt).pin
        try store.invalidate()
        #expect(domain.withLock { old.validateLocked(in: domain) } == .expired)
        try commit(stage(candidate, store: store), in: domain)
        let current = try store.preparedRetainedView(for: id, now: capture.createdAt).pin
        #expect(old.identity != current.identity)
        #expect(domain.withLock { old.validateLocked(in: domain) } == .expired)
        #expect(domain.withLock { current.validateLocked(in: domain) } == nil)
    }

    @Test func readPinsSurviveUnrelatedCreateAndSameRootAppendAfterLookup() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let firstCursor = cursorToken()
        let candidate = try bundle(capture, pages: [Data([1])], cursors: [firstCursor])
        let id = candidate.root.capture.metadata.snapshotId
        try commit(stage(candidate, store: store), in: domain)
        let oldRoot = try store.preparedRetainedView(for: id, now: capture.createdAt).pin
        let oldPage = try store.preparedPage(for: firstCursor, now: capture.createdAt).pin
        try commit(stage(bundle(capture), store: store), in: domain)
        let appended = try store.reserveAppend(snapshotID: id, pages: [Data([2])], cursors: [cursorToken()],
                                               publicationDeadline: capture.retentionDeadline)
        try commit(store.prepare(reservation: appended), in: domain)
        #expect(domain.withLock { oldRoot.validateLocked(in: domain) } == nil)
        #expect(domain.withLock { oldPage.validateLocked(in: domain) } == nil)
        let version = try domain.snapshot(for: store.publicationStoreID).version
        try commit(store.prepareAggregate([oldPage, oldRoot], in: domain), in: domain)
        #expect(try domain.snapshot(for: store.publicationStoreID).version == version)
        #expect(try store.page(for: firstCursor, now: capture.createdAt).encodedPage == Data([1]))
    }

    @Test func oldPinRejectsCompositeAppendAndRollsBackOtherwiseValidMutation() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        let id = candidate.root.capture.metadata.snapshotId
        try commit(stage(candidate, store: store), in: domain)
        let oldPin = try store.preparedRetainedView(for: id, now: capture.createdAt).pin
        try store.invalidate()
        try commit(stage(candidate, store: store), in: domain)
        let cursor = cursorToken()
        let reservation = try store.reserveAppend(snapshotID: id, pages: [Data([1, 2, 3])], cursors: [cursor],
                                                  publicationDeadline: capture.retentionDeadline)
        let mutation = try store.prepare(reservation: reservation)
        let composite = try store.prepareAggregate([oldPin, mutation], in: domain)
        let guarded = try #require(composite as? MCPReusableSnapshotGuardedPublication)
        let transferred = try #require(guarded.mutation)
        #expect(domain.withLock { transferred.validateLocked(in: domain) } == nil)
        #expect(domain.withLock { composite.validateLocked(in: domain) } == .expired)
        domain.withLock { composite.discardLocked(in: domain); composite.discardLocked(in: domain) }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
        #expect(try domain.accounting(for: store.publicationStoreID).visibleEntries == 1)
        #expect(throws: MCPReusableSnapshotError.invalidCursor) { try store.page(for: cursor, now: capture.createdAt) }
        #expect(try store.view(for: id, now: capture.createdAt).metadata.snapshotId == id)
    }

    @Test func eightDistinctRootsCompactRepeatedRootAndPagePinsWithinBound() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        var pins: [any MCPPreparedPublication] = []
        var ids: [String] = []
        for _ in 0..<8 {
            let cursor = cursorToken()
            let candidate = try bundle(capture, pages: [Data([1])], cursors: [cursor])
            try commit(stage(candidate, store: store), in: domain)
            let root = try store.preparedRetainedView(for: candidate.root.capture.metadata.snapshotId,
                                                     now: capture.createdAt).pin
            let page = try store.preparedPage(for: cursor, now: capture.createdAt).pin
            pins += [root, page, root, page]
            ids.append(root.snapshotID)
        }
        let aggregate = try store.prepareAggregate(pins, in: domain)
        let guarded = try #require(aggregate as? MCPReusableSnapshotGuardedPublication)
        #expect(guarded.pins.count == 8)
        #expect(guarded.pins.map(\.snapshotID) == ids.sorted())
        #expect(guarded.pins.allSatisfy { $0.cursor == nil })
        #expect(domain.withLock { aggregate.validateLocked(in: domain) } == nil)
        #expect(try domain.accounting(for: store.publicationStoreID).pendingEntries == 0)
    }

    @Test func moreThanEightDistinctPinnedRootsFailClosedWithoutReservation() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        var pins: [any MCPPreparedPublication] = []
        for _ in 0..<8 {
            let candidate = try bundle(capture)
            try commit(stage(candidate, store: store), in: domain)
            pins.append(try store.preparedRetainedView(for: candidate.root.capture.metadata.snapshotId,
                                                      now: capture.createdAt).pin)
        }
        try store.invalidate()
        let ninth = try bundle(capture)
        try commit(stage(ninth, store: store), in: domain)
        pins.append(try store.preparedRetainedView(for: ninth.root.capture.metadata.snapshotId,
                                                  now: capture.createdAt).pin)
        #expect(throws: PublicationRejection.busy) { try store.prepareAggregate(pins, in: domain) }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
    }

    @Test func conflictingSameIDPinIdentitiesCannotBeCompacted() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        let id = candidate.root.capture.metadata.snapshotId
        try commit(stage(candidate, store: store), in: domain)
        let old = try store.preparedRetainedView(for: id, now: capture.createdAt).pin
        try store.invalidate()
        try commit(stage(candidate, store: store), in: domain)
        let current = try store.preparedRetainedView(for: id, now: capture.createdAt).pin
        #expect(throws: PublicationRejection.busy) { try store.prepareAggregate([old, current], in: domain) }
        #expect(try domain.accounting(for: store.publicationStoreID).pendingEntries == 0)
    }

    @Test func readPinsAndAggregatesRejectOtherDomainsAndStores() throws {
        let capture = try MCPPortfolioSavedFixture().capture()
        let domain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let otherDomain = MCPReadPublicationDomain(testingInstant: capture.createdAt)
        let store = try MCPReusableSnapshotStore(domain: domain)
        let otherStore = try MCPReusableSnapshotStore(domain: domain)
        let candidate = try bundle(capture)
        try commit(stage(candidate, store: store), in: domain)
        let pin = try store.preparedRetainedView(for: candidate.root.capture.metadata.snapshotId,
                                                now: capture.createdAt).pin
        #expect(otherDomain.withLock { pin.validateLocked(in: otherDomain) } == .busy)
        #expect(throws: PublicationRejection.busy) { try store.prepareAggregate([pin], in: otherDomain) }
        #expect(throws: PublicationRejection.busy) { try otherStore.prepareAggregate([pin], in: domain) }
        let guarded = try store.prepareAggregate([pin], in: domain)
        #expect(otherDomain.withLock { guarded.validateLocked(in: otherDomain) } == .busy)
        #expect(try domain.accounting(for: store.publicationStoreID).pendingBytes == 0)
    }
}
#endif
