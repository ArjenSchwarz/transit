#if os(macOS)
import Foundation
import NIOConcurrencyHelpers
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPReadFrozenCursorGateTests {
    @Test(arguments: [false, true], [false, true])
    func cursorLookupCannotPublishAfterRootExpiryOrRetirement(modern: Bool, retire: Bool) async throws {
        let start = ContinuousClock.now
        // Original root began 299 seconds earlier; only its final second remains.
        let deadline = (start - .seconds(299)) + .seconds(300)
        let domain = MCPReadPublicationDomain(testingInstant: start)
        let store = MCPTaskQuerySnapshotStore(domain: domain)
        let cursor = store.makeCursor()
        let candidate = try prepareRoot(store: store, cursor: cursor, deadline: deadline, modern: modern)
        let publication = try #require(candidate)
        let (_, retired) = domain.withLockRetainingRetirement {
            #expect(publication.validateLocked(in: domain) == nil)
            publication.commitLocked(in: domain)
        }
        withExtendedLifetime(retired) {}
        let source = NoCapture()
        let service = MCPReadService(source: source,
            monitor: MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil), snapshots: store)
        let coordinator = MCPReadCoordinator(domain: domain)
        let id = JSONRPCId.string("frozen-cursor")
        let errors = try MCPBoundedReadDispatcher.publicationErrors(
            for: MCPReadToolRequest(tool: "query_tasks", arguments: ["cursor": AnyCodable(cursor)]),
            id: id, busy: Data("busy".utf8))
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: Data("busy".utf8)) { operation in
            do {
                let prepared = try await service.prepareRetainedPage(cursor: cursor, requestedPolicy: nil)
                #expect(prepared.publications.count == 1 && operation.shouldContinue())
                let guardPublication = try store.prepareAggregate(prepared.publications,
                    in: domain, operation: operation)
                let success = try MCPModernProviderBinding.read(prepared, id: id,
                    tool: "query_tasks", operation: operation)
                if retire { await store.clear() } else { domain.setTestingInstant(deadline) }
                #expect(operation.shouldContinue())
                return PreparedReadResult(encodedResponse: success, publications: [guardPublication],
                                          publicationErrors: errors)
            } catch {
                Issue.record("Unexpected cursor fixture error: \(error)")
                return PreparedReadResult(encodedResponse: Data("fixture-error".utf8), publications: [],
                                          publicationErrors: errors)
            }
        }
        let drainDeadline = ContinuousClock.now + .seconds(1)
        while coordinator.unfinishedCount != 0 && .now < drainDeadline { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0)
        #expect(bytes == errors.expired && bytes != Data("timeout".utf8))
        #expect(source.calls == 0)
        store.clear()
        let accounting = try domain.accounting(for: store.publicationStoreID)
        #expect(accounting.pendingBytes == 0 && accounting.visibleBytes == 0)
    }

    private func prepareRoot(store: MCPTaskQuerySnapshotStore, cursor: String,
                             deadline: ContinuousClock.Instant, modern: Bool) throws -> MCPPublicationReservation? {
        if modern {
            let pages = try ["[]", "null"].map { text in
                try MCPResultPreparation.page(request: MCPResultPagePreparationRequest(text: text,
                    isError: false, origin: .generatedJSON, evidence: .established,
                    context: MCPResultContext(tool: "query_tasks", semanticFailure: nil,
                        mutationRecovery: nil, entityPositions: []), metadataOwner: nil))
            }
            let bundle = try MCPResultPreparation.prepare(pages: pages,
                budget: MCPResultRetentionBudget(store: .ordinary, originalCaptureIndexBytes: 0,
                                                visibleBytes: 0, pendingBytes: 0))
            return try store.prepare(preparedBundle: bundle, cursors: [cursor],
                deadline: deadline, operationID: UUID(), metadataBytes: nil, policy: nil)
        } else {
            return try store.prepare(pages: ["[]", "null"], cursors: [cursor],
                deadline: deadline, operationID: UUID())
        }
    }

    @Test func byteComparisonChecksCancellationDuringTraversal() throws {
        let calls = NIOLockedValueBox(0)
        let text = String(repeating: "é", count: 10_000)
        #expect(throws: CancellationError.self) {
            try MCPReadSourceByteValidation.matches(text, text) {
                let count = calls.withLockedValue { $0 += 1; return $0 }
                if count == 3 { throw CancellationError() }
            }
        }
        #expect(calls.withLockedValue { $0 } == 3)
        #expect(try MCPReadSourceByteValidation.matches("", "", checkpoint: {}))
        #expect(try MCPReadSourceByteValidation.matches("é", "é", checkpoint: {}))
        #expect(try !MCPReadSourceByteValidation.matches("é", "e\u{301}", checkpoint: {}))
        #expect(try !MCPReadSourceByteValidation.matches("a", "ab", checkpoint: {}))
    }

    @MainActor private final class NoCapture: MCPReadCaptureSource {
        var calls = 0
        func capture(_ request: ReadCaptureRequest) throws -> CapturedReadView {
            calls += 1
            throw MCPReadCaptureError.storageFailure
        }
    }
}
#endif
