#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Owner-supplied reusable ABI; actual saved capture/comment closure has separate task16 coverage.
@MainActor @Suite(.serialized)
struct MCPModernReusableRetentionTests {
    @Test func reusableCaptureKeepsCommentCoveredRevisionAfterLaterSavedChanges() async throws {
        let models = try TestModelContainer()
        models.context.autosaveEnabled = false
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "blue")
        let task = TransitTask(name: "Saved", type: .feature, project: project, displayID: .permanent(16))
        let comment = Comment(content: "First", authorName: "Fixture", isAgent: true, task: task)
        models.context.insert(project)
        models.context.insert(task)
        models.context.insert(comment)
        try models.context.save()
        let revision = try MCPRecordSnapshot.task(task, in: models.context).revision
        let capture = try MCPReadCaptureBuilder(container: models.container, fence: .actorOnlyTestFixture)
            .capture(ReadCaptureRequest(projectSelectors: nil, selection: .portfolio,
                completeness: .completePortfolio, includeComments: false))
        await withOperation { operation in
            let fixture = try Fixture(capture: capture)
            let results = try fixture.results(fixture.pages())
            try fixture.commit(fixture.store.reservePreparedCreate(bundle: fixture.bundle,
                preparedResults: results, operation: operation, publicationDeadline: fixture.deadline))
            comment.content = "Second saved comment"
            task.name = "Second saved task"
            try models.context.save()
            #expect(try MCPRecordSnapshot.task(task, in: models.context).revision != revision)
            let retained = try fixture.store.preparedResultView(for: fixture.id, now: fixture.instant)
            let frozenTask = try #require(retained.root.capture.tasks.first)
            #expect(frozenTask.revision == revision && frozenTask.name == "Saved")
            #expect(frozenTask.requestedCommentRecordsJSON == nil)
            #expect(retained.root.capture.comments.first?.content == "First")
            #expect(retained.pin.deadline == capture.retentionDeadline)
            #expect(retained.root.frozenMetadataBytes == fixture.bundle.root.frozenMetadataBytes)
        }
    }

    @Test func legacyDefaultsRemainUsableAndModernCarrierCannotUseLegacyCharge() throws {
        let fixture = try Fixture()
        #expect(fixture.bundle.root.preparedResultPage == nil)
        #expect(fixture.bundle.preparedResultBundle == nil)
        let legacy = try fixture.store.reserveCreate(bundle: fixture.bundle, publicationDeadline: fixture.deadline)
        try fixture.commit(legacy)
        let root = try fixture.store.retainedView(for: fixture.id, now: fixture.instant)
        #expect(root.firstPage == fixture.bundle.root.firstPage)
        #expect(root.preparedResultPage == nil)
        #expect(throws: MCPReusableSnapshotError.incompatible) {
            try fixture.store.reserveAppend(snapshotID: fixture.id, pages: [], cursors: [],
                publicationDeadline: fixture.deadline)
        }
        let page = try fixture.pages()[0]
        let modernRoot = RetainedView(capture: root.capture, frozenMetadataBytes: root.frozenMetadataBytes,
            window: root.window, initialRequest: root.initialRequest, firstPage: root.firstPage,
            preparedResultPage: page)
        let guarded = EncodedViewBundle(root: modernRoot, pages: [], cursors: [], encodedCaptureByteCount: 128)
        #expect(throws: MCPResultPreparationError.notImplemented) {
            try fixture.store.reserveCreate(bundle: guarded, publicationDeadline: fixture.deadline)
        }
    }

    @Test func budgetObservesVisibleAndPendingWithoutCombiningOrdinaryStore() async {
        await withOperation { operation in
            let fixture = try Fixture()
            try fixture.commit(fixture.store.reserveCreate(bundle: fixture.bundle,
                publicationDeadline: fixture.deadline))
            let pendingFixture = try Fixture()
            let reservation = try fixture.store.reserveCreate(bundle: pendingFixture.bundle,
                publicationDeadline: fixture.deadline)
            defer { fixture.domain.withLock { reservation.publication.discardLocked(in: fixture.domain) } }
            let ordinary = MCPTaskQuerySnapshotStore(now: { fixture.instant }, domain: fixture.domain)
            try ordinary.publish(pages: ["ordinary-first", "ordinary-next"], cursors: [UUID().uuidString],
                deadline: fixture.deadline)
            let observed = try fixture.domain.accounting(for: fixture.store.publicationStoreID)
            let budget = try fixture.store.preparedResultBudget(originalCaptureIndexBytes: 257, operation: operation)
            #expect(budget.store == .reusable)
            #expect(budget.originalCaptureIndexBytes == 257)
            #expect(budget.visibleBytes == observed.visibleBytes)
            #expect(budget.visibleBytes > 0)
            #expect(budget.pendingBytes == observed.pendingBytes && budget.pendingBytes > 0)
            fixture.domain.withLock { reservation.publication.discardLocked(in: fixture.domain) }
            let clean = try fixture.store.preparedResultBudget(originalCaptureIndexBytes: 257, operation: operation)
            #expect(clean.pendingBytes == 0 && clean.visibleBytes == observed.visibleBytes)
        }
    }

    @Test func preparedCreateIsPrivateUntilGateWithExactExpandedChargeAndFrozenLookups() async {
        await withOperation { operation in
            let fixture = try Fixture()
            let pages = try fixture.pages()
            let results = try fixture.results(pages)
            let reservation = try fixture.store.reservePreparedCreate(bundle: fixture.bundle,
                preparedResults: results, operation: operation, publicationDeadline: fixture.deadline)
            defer { fixture.domain.withLock { reservation.publication.discardLocked(in: fixture.domain) } }
            #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
                try fixture.store.retainedView(for: fixture.id, now: fixture.instant)
            }
            let pending = try fixture.domain.accounting(for: fixture.store.publicationStoreID)
            #expect(pending.visibleEntries == 0 && pending.pendingEntries == 1)
            #expect(pending.pendingBytes == results.charge.totalBytes)
            try fixture.commit(reservation)
            let root = try fixture.store.preparedResultView(for: fixture.id, now: fixture.instant)
            let next = try fixture.store.preparedResultPage(for: fixture.cursor, now: fixture.instant)
            #expect(root.firstPage === pages[0])
            #expect(next.preparedPage === pages[1])
            #expect(next.page.preparedResultPage === pages[1])
            #expect(root.root.preparedResultPage === pages[0])
            #expect(root.pin.identity == next.pin.identity)
            #expect(root.pin.deadline == fixture.bundle.root.capture.retentionDeadline)
            #expect(next.page.root.frozenMetadataBytes == fixture.bundle.root.frozenMetadataBytes)
            #expect(root.firstPage.metadataOwner === next.preparedPage.metadataOwner)
            let visible = try fixture.domain.accounting(for: fixture.store.publicationStoreID)
            #expect(visible.visibleBytes == results.charge.totalBytes && visible.pendingBytes == 0)
            for id in [JSONRPCId.string("replay-new-id"), .integer(16)] {
                let first = try MCPResultEncoder.encode(fragment: next.preparedPage.fragment, id: id)
                #expect(first == (try MCPResultEncoder.encode(fragment: pages[1].fragment, id: id)))
            }
        }
    }

    @Test func zeroCursorAppendRetainsNewResponseOwnerAndSharedMetadataOnce() async {
        await withOperation { operation in
            let fixture = try Fixture()
            let pages = try fixture.pages()
            let first = try fixture.results(pages)
            try fixture.commit(fixture.store.reservePreparedCreate(bundle: fixture.bundle,
                preparedResults: first, operation: operation, publicationDeadline: fixture.deadline))
            let newPage = try fixture.page(#"{"projects":[],"later":true}"#, metadata: pages[0].metadataOwner)
            let expected = try fixture.results(pages + [newPage])
            let append = try fixture.store.reservePreparedAppend(snapshotID: fixture.id,
                pages: [], cursors: [], preparedPages: [newPage], operation: operation,
                publicationDeadline: fixture.deadline)
            try fixture.commit(append)
            let accounting = try fixture.domain.accounting(for: fixture.store.publicationStoreID)
            #expect(accounting.visibleBytes == expected.charge.totalBytes)
            let root = try fixture.store.preparedResultView(for: fixture.id, now: fixture.instant)
            #expect(root.firstPage === pages[0])
            #expect(root.pin.deadline == fixture.bundle.root.capture.retentionDeadline)
            #expect(newPage.metadataOwner === root.firstPage.metadataOwner)
        }
    }

    @Test func discardedPreparedCandidateReleasesPendingAndNeverPublishesTokens() async {
        await withOperation { operation in
            let fixture = try Fixture()
            let prepared = try fixture.results(fixture.pages())
            let reservation = try fixture.store.reservePreparedCreate(bundle: fixture.bundle,
                preparedResults: prepared, operation: operation, publicationDeadline: fixture.deadline)
            let before = try fixture.domain.accounting(for: fixture.store.publicationStoreID)
            #expect(before.pendingBytes == prepared.charge.totalBytes)
            fixture.domain.withLock {
                reservation.publication.discardLocked(in: fixture.domain)
                reservation.publication.discardLocked(in: fixture.domain)
            }
            let after = try fixture.domain.accounting(for: fixture.store.publicationStoreID)
            #expect(after.pendingBytes == 0 && after.pendingEntries == 0 && after.visibleEntries == 0)
            #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
                try fixture.store.retainedView(for: fixture.id, now: fixture.instant)
            }
            #expect(throws: MCPReusableSnapshotError.invalidCursor) {
                try fixture.store.page(for: fixture.cursor, now: fixture.instant)
            }
        }
    }

    @Test func expiredPreparedCandidateCannotPublishOrExtendOriginalFiveMinuteRoot() async {
        await withOperation { operation in
            let fixture = try Fixture()
            let results = try fixture.results(fixture.pages())
            let reservation = try fixture.store.reservePreparedCreate(bundle: fixture.bundle,
                preparedResults: results, operation: operation, publicationDeadline: fixture.deadline)
            defer { fixture.domain.withLock { reservation.publication.discardLocked(in: fixture.domain) } }
            fixture.domain.setTestingInstant(fixture.bundle.root.capture.retentionDeadline)
            #expect(fixture.domain.withLock {
                reservation.publication.validateLocked(in: fixture.domain)
            } == .expired)
            #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
                try fixture.store.retainedView(for: fixture.id, now: fixture.bundle.root.capture.retentionDeadline)
            }
            #expect(try fixture.domain.accounting(for: fixture.store.publicationStoreID).visibleEntries == 0)
        }
    }

    @Test func expandedPreparationFailsWholeAtReusableCapacityWithoutReservation() async throws {
        let largeFixture = try Fixture()
        // Build the immutable value outside the admission clock. Capacity measurement
        // below still uses the actual original operation and never widens its budget.
        let text = "{\"padding\":\"" + String(repeating: "x", count: 5 * 1_024 * 1_024) + "\"}"
        let page = try largeFixture.page(text, metadata: nil)
        await withOperation { operation in
            let fixture = try Fixture()
            // Raw text fits legacy Data accounting; tree/document/text/fragment together exceed 16MiB.
            let budget = try fixture.store.preparedResultBudget(originalCaptureIndexBytes: 128, operation: operation)
            #expect(throws: MCPResultPreparationError.retentionCapacity) {
                try MCPResultPreparation.prepare(pages: [page], budget: budget) {
                    guard operation.shouldContinue() else { throw CancellationError() }
                }
            }
            let accounting = try fixture.domain.accounting(for: fixture.store.publicationStoreID)
            #expect(accounting.pendingBytes == 0 && accounting.visibleBytes == 0)
        }
    }

    @Test(arguments: [false, true])
    func siblingAppendsShareExistingBaseButRejectNewSharedOwnerBeforeTransfer(sharedNew: Bool) async {
        await withOperation { operation in
            let fixture = try Fixture()
            let pages = try fixture.pages()
            try fixture.commit(fixture.store.reservePreparedCreate(bundle: fixture.bundle,
                preparedResults: fixture.results(pages), operation: operation, publicationDeadline: fixture.deadline))
            let existing = try #require(pages[0].metadataOwner)
            let metadata = sharedNew ? try MCPResultPreparation.metadata(value: existing.value) : existing
            let firstPage = try fixture.page(#"{"projects":[],"sibling":1}"#, metadata: metadata)
            let secondPage = try fixture.page(#"{"projects":[],"sibling":2}"#, metadata: metadata)
            let first = try fixture.store.reservePreparedAppend(snapshotID: fixture.id, pages: [], cursors: [],
                preparedPages: [firstPage], operation: operation, publicationDeadline: fixture.deadline)
            defer { fixture.domain.withLock { first.publication.discardLocked(in: fixture.domain) } }
            let second: RetentionReservation
            let beforeSecond = try fixture.domain.accounting(for: fixture.store.publicationStoreID)
            do {
                second = try fixture.store.reservePreparedAppend(snapshotID: fixture.id, pages: [], cursors: [],
                    preparedPages: [secondPage], operation: operation, publicationDeadline: fixture.deadline)
            } catch {
                guard sharedNew, Self.isOwnerMisuse(error) else { throw error }
                #expect(operation.shouldContinue())
                #expect(try fixture.domain.accounting(for: fixture.store.publicationStoreID) == beforeSecond)
                #expect(first.publication.status == .pending)
                return
            }
            defer { fixture.domain.withLock { second.publication.discardLocked(in: fixture.domain) } }
            let before = try fixture.domain.accounting(for: fixture.store.publicationStoreID)
            if sharedNew {
                try self.requireAggregateMisuse(fixture: fixture, first: first, second: second)
                #expect(try fixture.domain.accounting(for: fixture.store.publicationStoreID) == before)
                #expect(first.publication.status == .pending && second.publication.status == .pending)
            } else {
                let expected = try fixture.results(pages + [firstPage, secondPage])
                #expect(before.pendingBytes == expected.charge.totalBytes - before.visibleBytes)
                let aggregate = try fixture.store.prepareAggregate([first.publication, second.publication],
                    in: fixture.domain)
                try fixture.domain.withLock {
                    if let rejection = aggregate.validateLocked(in: fixture.domain) { throw rejection }
                    aggregate.commitLocked(in: fixture.domain)
                }
                let after = try fixture.domain.accounting(for: fixture.store.publicationStoreID)
                #expect(after.visibleBytes == expected.charge.totalBytes && after.pendingBytes == 0)
                #expect(firstPage.metadataOwner === secondPage.metadataOwner)
            }
        }
    }

}

extension MCPModernReusableRetentionTests {
    private static func isOwnerMisuse(_ error: any Error) -> Bool {
        (error as? MCPReusableSnapshotError) == .incompatible || (error as? PublicationRejection) == .busy
    }

    private func requireAggregateMisuse(fixture: Fixture, first: RetentionReservation,
                                       second: RetentionReservation) throws {
        do {
            _ = try fixture.store.prepareAggregate([first.publication, second.publication], in: fixture.domain)
            Issue.record("New shared sibling owner unexpectedly transferred")
        } catch { #expect(Self.isOwnerMisuse(error)) }
    }

    private func withOperation(_ body: @escaping @MainActor @Sendable (MCPReadOperation) throws -> Void) async {
        let coordinator = MCPReadCoordinator()
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            await MainActor.run {
                do { try body(operation); return Self.result(Data("completed".utf8)) } catch {
                    Issue.record("Modern reusable retention failed: \(error)")
                    return Self.result(Data("failed".utf8))
                }
            }
        }
        #expect(bytes == Data("completed".utf8))
        for _ in 0..<100 where coordinator.unfinishedCount != 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(coordinator.unfinishedCount == 0)
    }

    nonisolated private static func result(_ bytes: Data) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: bytes, publications: [],
            publicationErrors: .init(busy: Data(), expired: Data(), capacity: Data()))
    }
}

@MainActor
private struct Fixture {
    let instant: ContinuousClock.Instant
    let deadline: ContinuousClock.Instant
    let domain: MCPReadPublicationDomain
    let store: MCPReusableSnapshotStore
    let id: String
    let cursor: String
    let bundle: EncodedViewBundle

    init(capture savedCapture: CapturedReadView? = nil) throws {
        instant = savedCapture?.createdAt ?? .now
        deadline = savedCapture?.retentionDeadline ?? instant.advanced(by: .seconds(300))
        domain = MCPReadPublicationDomain(testingInstant: instant)
        store = try MCPReusableSnapshotStore(domain: domain)
        id = savedCapture?.metadata.snapshotId ?? UUID().uuidString
        cursor = "00000000-0000-8000-8000-" + UUID().uuidString.suffix(12)
        let metadata = ReadCaptureMetadata(asOf: "2026-10-04T09:00:00.000Z", snapshotId: id,
            freshness: ReadFreshness(syncState: .inactive, assessment: .notApplicable,
                assessedAt: "2026-10-04T09:00:00.000Z", lastImportedAt: nil,
                evidence: .none, recentImportThresholdMs: 60_000),
            read: ReadExecutionMetadata(policy: .cached, refreshOutcome: .notRequested, budgetMs: 5_000))
        let capture = savedCapture ?? CapturedReadView(completeness: .completePortfolio, captureScope: .wholePortfolio,
            metadata: metadata, createdAt: instant, retentionDeadline: deadline,
            projects: [], tasks: [], milestones: [], comments: [])
        let window = try CompletionWindow.parse(start: "2026-10-01T00:00:00Z", end: "2026-10-04T00:00:00Z")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let root = RetainedView(capture: capture, frozenMetadataBytes: try encoder.encode(capture.metadata),
            window: window,
            initialRequest: .initial(window: window, limit: 1, project: nil, policy: .cached),
            firstPage: Data(#"{"projects":[],"first":true}"#.utf8))
        bundle = EncodedViewBundle(root: root, pages: [Data(#"{"projects":[],"next":true}"#.utf8)],
            cursors: [cursor], encodedCaptureByteCount: 128)
    }

    func pages() throws -> [MCPResultPreparedPage] {
        let read = try MCPPreparedToolRead(text: "null", frozenMetadataBytes: bundle.root.frozenMetadataBytes)
        let value = try #require(try MCPResultProviderAdapters.metadata(result: read.result,
            frozenReadBytes: bundle.root.frozenMetadataBytes))
        let metadata = try MCPResultPreparation.metadata(value: value)
        return try ([bundle.root.firstPage] + bundle.pages).map {
            try page(try #require(String(data: $0, encoding: .utf8)), metadata: metadata)
        }
    }

    func page(_ text: String, metadata: MCPResultPreparedMetadata?) throws -> MCPResultPreparedPage {
        try MCPResultPreparation.page(request: MCPResultPagePreparationRequest(text: text, isError: nil,
            origin: .generatedJSON, evidence: .established,
            context: MCPResultContext(tool: "query_project_summaries", semanticFailure: nil,
                mutationRecovery: nil, entityPositions: []), metadataOwner: metadata))
    }

    func results(_ pages: [MCPResultPreparedPage]) throws -> MCPResultRetainedBundle {
        // Existing legacy copies remain retained alongside frozen modern owners.
        let original = bundle.encodedCaptureByteCount + bundle.root.firstPage.count
            + bundle.pages.reduce(0) { $0 + $1.count } + bundle.root.frozenMetadataBytes.count
        return try MCPResultPreparation.prepare(pages: pages, budget: MCPResultRetentionBudget(store: .reusable,
            originalCaptureIndexBytes: original, visibleBytes: 0, pendingBytes: 0))
    }

    func commit(_ reservation: RetentionReservation) throws {
        let publication = try store.prepare(reservation: reservation)
        try domain.withLock {
            if let rejection = publication.validateLocked(in: domain) { throw rejection }
            publication.commitLocked(in: domain)
        }
    }
}
#endif
