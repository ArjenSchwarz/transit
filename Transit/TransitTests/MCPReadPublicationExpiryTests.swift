#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Common gate proof with real store reservations; owner helper implementation remains separate acceptance.
@MainActor @Suite(.serialized)
struct MCPReadPublicationExpiryTests {
    private let snapshotID = "11111111-1111-4111-8111-111111111111"
    private let reusableCursor = "22222222-2222-8222-8222-222222222222"

    @Test(arguments: 0..<6)
    func expiredPublicationSelectsFamilyErrorAndDiscardsCandidate(mode: Int) async throws {
        let request = request(mode: mode)
        let id = JSONRPCId.string("expiry-\"\\-\(mode)")
        let busy = Data("busy-sentinel".utf8)
        let errors = try MCPBoundedReadDispatcher.publicationErrors(for: request, id: id, busy: busy)
        #expect(errors.busy == busy)
        #expect(try errorCode(errors.capacity) == "QUERY_CAPACITY_EXCEEDED")
        let start = ContinuousClock.now
        let expiry = start + .seconds(300)
        let domain = MCPReadPublicationDomain(testingInstant: start)
        let coordinator = MCPReadCoordinator(domain: domain)
        let prepared = try candidate(mode: mode, domain: domain, start: start)
        let publication = prepared.publication
        let storeID = publication.publicationStoreID
        let before = try domain.accounting(for: storeID)
        #expect(before.visibleEntries == 0 && before.visibleBytes == 0)
        #expect(before.pendingEntries == 1 && before.pendingBytes > 0)
        let bytes = await coordinator.execute(timeout: Data("timeout".utf8), busy: busy) { _ in
            domain.setTestingInstant(expiry)
            return PreparedReadResult(encodedResponse: Data("unpublished-success".utf8),
                                      publications: [publication], publicationErrors: errors)
        }
        let drainDeadline = ContinuousClock.now + .seconds(1)
        while coordinator.unfinishedCount != 0 && .now < drainDeadline { await Task.yield() }
        #expect(coordinator.unfinishedCount == 0)
        let after = try domain.accounting(for: storeID)
        #expect(after.visibleEntries == 0 && after.visibleBytes == 0)
        #expect(after.pendingEntries == 0 && after.pendingBytes == 0)
        let frame = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(frame["id"] as? String == "expiry-\"\\-\(mode)")
        let result = try #require(frame["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
        #expect(result["_meta"] == nil)
        let expected = mode == 0 ? "QUERY_EXPIRED" : (mode == 2 || mode == 5 ? "INVALID_CURSOR" : "INVALID_SNAPSHOT")
        #expect(try errorCode(bytes) == expected)
        // Store ownership stays alive through final accounting and outside-lock retirement.
        withExtendedLifetime(prepared.store) {}
    }

    private func request(mode: Int) -> MCPReadToolRequest {
        let tool = mode < 3 ? "query_tasks" : "query_project_summaries"
        let arguments: [String: AnyCodable]
        switch mode {
        case 0: arguments = ["detailLevel": AnyCodable("summary"), "includeComments": AnyCodable(false),
                             "limit": AnyCodable(1)]
        case 1: arguments = ["snapshotId": AnyCodable(snapshotID)]
        case 2, 5: arguments = ["cursor": AnyCodable(reusableCursor)]
        case 3: arguments = ["start": AnyCodable("2026-01-01T00:00:00Z"),
                             "end": AnyCodable("2026-02-01T00:00:00Z"), "limit": AnyCodable(1)]
        default: arguments = ["snapshotId": AnyCodable(snapshotID)]
        }
        return MCPReadToolRequest(tool: tool, arguments: arguments)
    }

    private func candidate(mode: Int, domain: MCPReadPublicationDomain, start: ContinuousClock.Instant)
        throws -> Candidate {
        let expiry = start + .seconds(300)
        if mode == 0 {
            let store = MCPTaskQuerySnapshotStore(domain: domain)
            let candidate = try store.prepare(pages: ["first", "second"],
                cursors: [store.makeCursor()], deadline: expiry, operationID: UUID())
            let publication = try #require(candidate)
            return Candidate(store: store, publication: publication)
        }
        let store = try MCPReusableSnapshotStore(domain: domain)
        let metadata = ReadCaptureMetadata(asOf: "2026-01-01T00:00:00.000Z", snapshotId: snapshotID,
            freshness: ReadFreshness(syncState: .inactive, assessment: .notApplicable,
                assessedAt: "2026-01-01T00:00:00.000Z", lastImportedAt: nil, evidence: .none,
                recentImportThresholdMs: 60_000),
            read: ReadExecutionMetadata(policy: .cached, refreshOutcome: .notRequested, budgetMs: 5_000))
        let view = CapturedReadView(completeness: .completePortfolio, captureScope: .wholePortfolio,
            metadata: metadata, createdAt: start, retentionDeadline: expiry,
            projects: [], tasks: [], milestones: [], comments: [])
        let window = CompletionWindow(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1))
        let frozenMetadata = try JSONEncoder().encode(metadata)
        let root = RetainedView(capture: view, frozenMetadataBytes: frozenMetadata,
            window: window, initialRequest: .initial(window: window, limit: 1, project: nil, policy: .cached),
            firstPage: Data("first".utf8))
        let reservation = try store.reserveCreate(bundle: EncodedViewBundle(root: root,
            pages: [Data("next".utf8)], cursors: [reusableCursor],
            encodedCaptureByteCount: frozenMetadata.count), publicationDeadline: expiry + .seconds(1))
        // The domain clock expires the retained root while the reservation deadline remains live.
        #expect(reservation.publication.deadline > expiry)
        return Candidate(store: store, publication: try store.prepare(reservation: reservation))
    }

    private func errorCode(_ bytes: Data) throws -> String {
        let frame = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let payload = try MCPTestHelpers.decodeHTTPToolResult(frame)
        let error = try #require(payload["error"] as? [String: Any])
        return try #require(error["code"] as? String)
    }

    private struct Candidate {
        let store: AnyObject
        let publication: any MCPPreparedPublication
    }
}
#endif
