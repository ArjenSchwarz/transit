#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// RED preparation: successful retention is required; notImplemented is a behavioral failure.
@MainActor @Suite(.serialized)
struct MCPReusableSnapshotPreparedOwnerTests {
    @Test func sharedBaseMetadataAndPagesRemainOneOwnerAcrossAppend() async throws {
        let env = try Environment()
        await withOperation(env) { operation in
            let root = try self.create(env, operation: operation)
            let base = try env.store.domain.accounting(for: env.store.publicationStoreID)
            let metadata = try #require(root.owners.first?.metadataOwner)
            let left = try self.pages(metadata: metadata, operation: operation)
            let right = try self.pages(metadata: metadata, operation: operation)
            #expect(left[0] !== right[0] && left[0].metadataOwner === right[0].metadataOwner)
            let firstCursor = self.cursor()
            let secondCursor = self.cursor()
            let first = try self.append(env, root: root, pages: left, cursor: firstCursor, operation: operation)
            defer { try? env.store.rollback(first) }
            let second = try self.append(env, root: root, pages: right, cursor: secondCursor, operation: operation)
            defer { try? env.store.rollback(second) }
            let children = try [env.store.prepare(reservation: first), env.store.prepare(reservation: second)]
            let pending = try env.store.domain.accounting(for: env.store.publicationStoreID)
            let legacy = root.legacyBytes + left[1].source.originalText.utf8.count
                + right[1].source.originalText.utf8.count
            let expected = try self.measure(root.owners + left + right, legacyBytes: legacy, operation: operation)
            #expect(pending.pendingBytes == expected.charge.totalBytes - base.visibleBytes)
            let aggregate = try env.store.prepareAggregate(children, in: env.store.domain)
            try self.commit(aggregate, env: env)
            let accounting = try env.store.domain.accounting(for: env.store.publicationStoreID)
            #expect(accounting.visibleBytes == expected.charge.totalBytes && accounting.pendingBytes == 0)
            let pinned = try env.store.preparedResultView(for: root.id, now: .now)
            let firstPage = try env.store.preparedResultPage(for: firstCursor, now: .now)
            let secondPage = try env.store.preparedResultPage(for: secondCursor, now: .now)
            #expect(pinned.firstPage === root.owners[0] && firstPage.preparedPage === left[1])
            #expect(secondPage.preparedPage === right[1] && pinned.firstPage.metadataOwner === metadata)
            #expect(firstPage.preparedPage.metadataOwner === metadata
                    && secondPage.preparedPage.metadataOwner === metadata)
            #expect(firstPage.page.root.capture.retentionDeadline == root.bundle.root.capture.retentionDeadline)
        }
    }

    @Test func equalBytesWithDistinctNewSiblingOwnersPublishBothChanges() async throws {
        let env = try Environment()
        await withOperation(env) { operation in
            let root = try self.create(env, operation: operation)
            let left = try self.pages(metadata: self.metadata(root.bundle.root), operation: operation)
            let right = try self.pages(metadata: self.metadata(root.bundle.root), operation: operation)
            #expect(left[0] !== right[0] && left[0].metadataOwner !== right[0].metadataOwner)
            #expect(left[0].fragment.encodedResult == right[0].fragment.encodedResult)
            let firstCursor = self.cursor()
            let secondCursor = self.cursor()
            let first = try self.append(env, root: root, pages: left, cursor: firstCursor, operation: operation)
            defer { try? env.store.rollback(first) }
            let second = try self.append(env, root: root, pages: right, cursor: secondCursor, operation: operation)
            defer { try? env.store.rollback(second) }
            let children = try [env.store.prepare(reservation: first), env.store.prepare(reservation: second)]
            let aggregate = try env.store.prepareAggregate(children, in: env.store.domain)
            try self.commit(aggregate, env: env)
            #expect(try env.store.preparedResultPage(for: firstCursor, now: .now).preparedPage === left[1])
            #expect(try env.store.preparedResultPage(for: secondCursor, now: .now).preparedPage === right[1])
            let legacy = root.legacyBytes + left[1].source.originalText.utf8.count
                + right[1].source.originalText.utf8.count
            let expected = try self.measure(root.owners + left + right, legacyBytes: legacy, operation: operation)
            let accounting = try env.store.domain.accounting(for: env.store.publicationStoreID)
            #expect(accounting.visibleBytes == expected.charge.totalBytes && accounting.pendingBytes == 0)
        }
    }

    @Test(arguments: ["page", "metadata"])
    func sharedNewSiblingOwnerRejectsWithoutMutatingReservations(kind: String) async throws {
        let env = try Environment()
        await withOperation(env) { operation in
            let root = try self.create(env, operation: operation)
            let newMetadata = try self.metadata(root.bundle.root)
            let left = try self.pages(metadata: newMetadata, operation: operation)
            let right = kind == "page" ? left : try self.pages(metadata: newMetadata, operation: operation)
            #expect(left[0].metadataOwner === right[0].metadataOwner)
            #expect((left[0] === right[0]) == (kind == "page"))
            let first = try self.append(env, root: root, pages: left, cursor: self.cursor(), operation: operation)
            defer { try? env.store.rollback(first) }
            let second = try self.append(env, root: root, pages: right, cursor: self.cursor(), operation: operation)
            defer { try? env.store.rollback(second) }
            let children = try [env.store.prepare(reservation: first), env.store.prepare(reservation: second)]
            let before = try env.store.domain.snapshot(for: env.store.publicationStoreID)
            let accounting = try env.store.domain.accounting(for: env.store.publicationStoreID)
            #expect(throws: PublicationRejection.busy) {
                try env.store.prepareAggregate(children, in: env.store.domain)
            }
            let after = try env.store.domain.snapshot(for: env.store.publicationStoreID)
            #expect(after.version == before.version && after.tokenVersion == before.tokenVersion)
            #expect(ObjectIdentifier(after.index) == ObjectIdentifier(before.index))
            #expect(after.allocatedTokenSets == before.allocatedTokenSets)
            #expect(try env.store.domain.accounting(for: env.store.publicationStoreID) == accounting)
            for child in children {
                #expect(env.store.domain.withLock { child.validateLocked(in: env.store.domain) } == nil)
            }
        }
    }

    /// Cross-root owners also violate provenance; this does not isolate overlap-detection precedence.
    @Test func crossRootOwnerMisuseRejectsWithoutChangingPendingState() async throws {
        let env = try Environment()
        await withOperation(env) { operation in
            let firstRoot = try self.create(env, operation: operation)
            let secondRoot = try self.create(env, operation: operation)
            let shared = try self.pages(metadata: self.metadata(firstRoot.bundle.root), operation: operation)
            let first = try self.append(env, root: firstRoot, pages: shared,
                cursor: self.cursor(), operation: operation)
            defer { try? env.store.rollback(first) }
            let firstChild = try env.store.prepare(reservation: first)
            var before = try env.store.domain.snapshot(for: env.store.publicationStoreID)
            var accounting = try env.store.domain.accounting(for: env.store.publicationStoreID)
            var children = [firstChild]
            var unexpected: (any MCPPreparedPublication)?
            do {
                let second = try self.append(env, root: secondRoot, pages: shared,
                    cursor: self.cursor(), operation: operation)
                defer { try? env.store.rollback(second) }
                children.append(try env.store.prepare(reservation: second))
                before = try env.store.domain.snapshot(for: env.store.publicationStoreID)
                accounting = try env.store.domain.accounting(for: env.store.publicationStoreID)
                do {
                    unexpected = try env.store.prepareAggregate(children, in: env.store.domain)
                    Issue.record("Cross-root owner misuse unexpectedly produced an aggregate")
                } catch {
                    #expect(self.isOwnerMisuseRejection(error))
                }
                let after = try env.store.domain.snapshot(for: env.store.publicationStoreID)
                #expect(after.version == before.version && after.tokenVersion == before.tokenVersion)
                #expect(ObjectIdentifier(after.index) == ObjectIdentifier(before.index))
                #expect(after.allocatedTokenSets == before.allocatedTokenSets)
                #expect(try env.store.domain.accounting(for: env.store.publicationStoreID) == accounting)
                for child in children {
                    #expect(env.store.domain.withLock { child.validateLocked(in: env.store.domain) } == nil)
                }
                if let unexpected {
                    env.store.domain.withLock { unexpected.discardLocked(in: env.store.domain) }
                }
            } catch {
                #expect(self.isOwnerMisuseRejection(error))
                let after = try env.store.domain.snapshot(for: env.store.publicationStoreID)
                #expect(after.version == before.version && after.tokenVersion == before.tokenVersion)
                #expect(ObjectIdentifier(after.index) == ObjectIdentifier(before.index))
                #expect(after.allocatedTokenSets == before.allocatedTokenSets)
                #expect(try env.store.domain.accounting(for: env.store.publicationStoreID) == accounting)
                #expect(env.store.domain.withLock { firstChild.validateLocked(in: env.store.domain) } == nil)
            }
        }
    }

    @Test func firstOnlyAppendIsChargedAndDoesNotReplaceOriginalSummaryOwner() async throws {
        let env = try Environment()
        await withOperation(env) { operation in
            let root = try self.create(env, operation: operation)
            let added = try self.pages(metadata: self.metadata(root.bundle.root), operation: operation)[0]
            let reservation = try env.store.reservePreparedAppend(snapshotID: root.id, pages: [], cursors: [],
                preparedPages: [added], operation: operation, publicationDeadline: .now + operation.remainingBudget())
            defer { try? env.store.rollback(reservation) }
            try self.commit(env.store.prepare(reservation: reservation), env: env)
            let expected = try self.measure(root.owners + [added], legacyBytes: root.legacyBytes, operation: operation)
            #expect(try env.store.domain.accounting(for: env.store.publicationStoreID).visibleBytes
                    == expected.charge.totalBytes)
            #expect(try env.store.preparedResultView(for: root.id, now: .now).firstPage === root.owners[0])
        }
    }

    @Test func retiringOneRootPreservesIndependentlyMeasuredSurvivorCharge() async throws {
        let env = try Environment()
        await withOperation(env) { operation in
            let earlier = try self.create(env, operation: operation)
            let later = try self.create(env, operation: operation)
            #expect(later.bundle.root.capture.retentionDeadline > earlier.bundle.root.capture.retentionDeadline)
            #expect(later.owners[0] !== earlier.owners[0])
            #expect(later.owners[0].metadataOwner !== earlier.owners[0].metadataOwner)
            env.retirement = Retirement(earlier: earlier, later: later)
        }
        let roots = try #require(env.retirement)
        env.store.domain.setTestingInstant(roots.earlier.bundle.root.capture.retentionDeadline)
        let surviving = try env.store.preparedResultView(for: roots.later.id,
            now: roots.earlier.bundle.root.capture.retentionDeadline)
        #expect(surviving.firstPage === roots.later.owners[0])
        let accounting = try env.store.domain.accounting(for: env.store.publicationStoreID)
        #expect(accounting.visibleEntries == 1 && accounting.visibleBytes == roots.later.measured.charge.totalBytes)
        #expect(accounting.pendingEntries == 0 && accounting.pendingBytes == 0)
        #expect(throws: MCPReusableSnapshotError.invalidSnapshot) {
            try env.store.preparedResultView(for: roots.earlier.id,
                now: roots.earlier.bundle.root.capture.retentionDeadline)
        }
        try env.store.invalidate()
        #expect(try env.store.domain.accounting(for: env.store.publicationStoreID).visibleBytes == 0)
    }
}

private extension MCPReusableSnapshotPreparedOwnerTests {
    struct Root {
        let bundle: EncodedViewBundle
        let owners: [MCPResultPreparedPage]
        let measured: MCPResultRetainedBundle
        let legacyBytes: Int
        var id: String { bundle.root.capture.metadata.snapshotId }
    }
    struct Retirement { let earlier: Root; let later: Root }

    @MainActor final class Environment {
        let fixture: MCPPortfolioSavedFixture
        let store: MCPReusableSnapshotStore
        let coordinator: MCPReadCoordinator
        var retirement: Retirement?
        init() throws {
            fixture = try MCPPortfolioSavedFixture()
            let domain = MCPReadPublicationDomain()
            store = try MCPReusableSnapshotStore(domain: domain)
            coordinator = MCPReadCoordinator(domain: domain)
        }
    }

    func isOwnerMisuseRejection(_ error: Error) -> Bool {
        (error as? MCPReusableSnapshotError) == .incompatible || (error as? PublicationRejection) == .busy
    }

    func cursor() -> String { MCPReusableSnapshotStoreTests().cursorToken() }

    func metadata(_ root: RetainedView) throws -> MCPResultPreparedMetadata {
        let read = try MCPPreparedToolRead(text: "{}", frozenMetadataBytes: root.frozenMetadataBytes)
        let value = try #require(try MCPResultProviderAdapters.metadata(result: read.result,
            frozenReadBytes: root.frozenMetadataBytes))
        return try MCPResultPreparation.metadata(value: value)
    }

    func pages(metadata: MCPResultPreparedMetadata, operation: MCPReadOperation) throws -> [MCPResultPreparedPage] {
        try [0, 1].map { number in
            try MCPResultPreparation.page(request: MCPResultPagePreparationRequest(text: "{\"page\":\(number)}",
                isError: false, origin: .generatedJSON, evidence: .established,
                context: MCPResultContext(tool: "query_tasks", semanticFailure: nil,
                    mutationRecovery: nil, entityPositions: []), metadataOwner: metadata),
                checkpoint: { try MCPPortfolioReadEncoding.check(operation) })
        }
    }

    func measure(_ owners: [MCPResultPreparedPage], legacyBytes: Int,
                 operation: MCPReadOperation) throws -> MCPResultRetainedBundle {
        try MCPResultPreparation.prepare(pages: owners, budget: MCPResultRetentionBudget(store: .reusable,
            originalCaptureIndexBytes: legacyBytes, visibleBytes: 0, pendingBytes: 0),
            checkpoint: { try MCPPortfolioReadEncoding.check(operation) })
    }

    func create(_ env: Environment, operation: MCPReadOperation) throws -> Root {
        let capture = try env.fixture.capture()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(capture.metadata)
        let capsule = MCPPreparedReadCapture(view: capture, frozenMetadataBytes: bytes)
        let captureBytes = try MCPPortfolioCaptureCharge.bytes(capsule, operation: operation)
        let initial = RetainedView(capture: capture, frozenMetadataBytes: bytes, window: MCPPortfolioFixture.window,
            initialRequest: .initial(window: MCPPortfolioFixture.window, limit: 1, project: nil, policy: .cached),
            firstPage: Data("{\"page\":0}".utf8))
        let owners = try pages(metadata: metadata(initial), operation: operation)
        let cursor = cursor()
        let continuation = Data(owners[1].source.originalText.utf8)
        let legacyBytes = try MCPResultRetentionAccounting.add(captureBytes,
            MCPResultRetentionAccounting.add(initial.firstPage.count, continuation.count))
        let budget = try env.store.preparedResultBudget(originalCaptureIndexBytes: legacyBytes, operation: operation)
        let measured = try MCPResultPreparation.prepare(pages: owners, budget: budget,
            checkpoint: { try MCPPortfolioReadEncoding.check(operation) })
        let root = RetainedView(capture: capture, frozenMetadataBytes: bytes, window: initial.window,
            initialRequest: initial.initialRequest, firstPage: initial.firstPage, preparedResultPage: owners[0])
        let bundle = EncodedViewBundle(root: root, pages: [continuation], cursors: [cursor],
            encodedCaptureByteCount: captureBytes, preparedResultBundle: measured)
        let reservation = try env.store.reservePreparedCreate(bundle: bundle, preparedResults: measured,
            operation: operation, publicationDeadline: .now + operation.remainingBudget())
        defer { try? env.store.rollback(reservation) }
        try commit(env.store.prepare(reservation: reservation), env: env)
        #expect(try env.store.preparedResultPage(for: cursor, now: .now).preparedPage === owners[1])
        return Root(bundle: bundle, owners: owners, measured: measured, legacyBytes: legacyBytes)
    }

    func append(_ env: Environment, root: Root, pages: [MCPResultPreparedPage], cursor: String,
                operation: MCPReadOperation) throws -> RetentionReservation {
        try env.store.reservePreparedAppend(snapshotID: root.id,
            pages: [Data(pages[1].source.originalText.utf8)], cursors: [cursor], preparedPages: pages,
            operation: operation, publicationDeadline: .now + operation.remainingBudget())
    }

    func commit(_ publication: any MCPPreparedPublication, env: Environment) throws {
        try MCPReusableSnapshotStoreTests().commit(publication, in: env.store.domain)
    }

    func withOperation(_ env: Environment,
                       body: @escaping @MainActor @Sendable (MCPReadOperation) throws -> Void) async {
        let success = Data("finished".utf8)
        let response = await env.coordinator.execute(
            timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            do {
                try await MainActor.run { try body(operation) }
            } catch {
                Issue.record("Required prepared-retention behavior failed: \(error)")
            }
            return PreparedReadResult(encodedResponse: success, publications: [],
                publicationErrors: PreencodedPublicationErrors(busy: Data(), expired: Data(), capacity: Data()))
        }
        #expect(response == success)
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while env.coordinator.unfinishedCount != 0 && ContinuousClock.now < deadline {
            await Task.detached { try? await Task.sleep(for: .milliseconds(25)) }.value
        }
        #expect(env.coordinator.unfinishedCount == 0)
        withExtendedLifetime(env.fixture) {}
    }
}
#endif
