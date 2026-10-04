#if os(macOS)
import Foundation

extension MCPReadService {
    func prepareRetainedPage(cursor: String, requestedPolicy: MCPReadPolicy?) throws -> MCPPreparedToolRead {
        let (page, pin) = try snapshots.preparedRetainedPage(for: cursor)
        if let requestedPolicy, let retained = page.policy, requestedPolicy != retained {
            throw MCPTaskQueryError(code: "INVALID_INPUT", message: "readPolicy conflicts with retained query")
        }
        if let owner = page.preparedResultPage {
            return MCPPreparedToolRead(preparedResultPage: owner, frozenMetadataBytes: page.metadataBytes,
                                       publications: [pin])
        }
        return try MCPPreparedToolRead(text: page.text, frozenMetadataBytes: page.metadataBytes, publications: [pin])
    }

    func preparePages(_ results: [[String: Any]], query: MCPTaskQueryRequest,
                      view: CapturedReadView, operation: MCPReadOperation,
                      frozenMetadataBytes: Data) throws -> MCPPreparedToolRead {
        let count = max(1, (results.count + query.limit - 1) / query.limit)
        let cursors = (0..<(count - 1)).map { _ in snapshots.makeCursor() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let asOf = formatter.date(from: view.metadata.asOf) else {
            throw MCPReadCaptureError.incoherentCapture
        }
        let expiry = ISO8601DateFormatter().string(from: asOf.addingTimeInterval(300))
        let pages = try (0..<count).map { position in
            guard operation.shouldContinue() else { throw CancellationError() }
            let start = position * query.limit
            let end = min(start + query.limit, results.count)
            let next: Any = position < cursors.count ? cursors[position] : NSNull()
            return try jsonText(["results": Array(results[start..<end]), "nextCursor": next, "expiresAt": expiry])
        }
        guard operation.shouldContinue() else { throw CancellationError() }
        let tools = try pages.map { text in
            guard operation.shouldContinue() else { throw CancellationError() }
            return try MCPPreparedToolRead(text: text, metadata: .capture(view.metadata),
                                          frozenMetadataBytes: frozenMetadataBytes)
        }
        if let owners = try preparePrivatePages(tools, tool: "query_tasks", operation: operation) {
            guard owners.count == tools.count, let first = owners.first else {
                throw MCPReadCaptureError.incoherentCapture
            }
            let checkpoint: @Sendable () throws -> Void = {
                guard operation.shouldContinue() else { throw CancellationError() }
            }
            let usage = try snapshots.domain.accounting(for: snapshots.publicationStoreID)
            // No model capture is retained in ordinary indexes. Raw metadata is charged by the store.
            let bundle = try MCPResultPreparation.prepare(pages: owners,
                budget: MCPResultRetentionBudget(store: .ordinary, originalCaptureIndexBytes: 0,
                    visibleBytes: usage.visibleBytes, pendingBytes: usage.pendingBytes), checkpoint: checkpoint)
            let publication = try snapshots.prepare(preparedBundle: bundle, cursors: cursors,
                deadline: view.retentionDeadline, operationID: operation.id, metadataBytes: frozenMetadataBytes,
                policy: view.metadata.read.policy, operation: operation)
            return tools[0].attachingPreparedResultPage(first).attaching(publication.map { [$0] } ?? [])
        }
        let first = tools[0]
        let reservation = try snapshots.prepare(pages: pages, cursors: cursors, deadline: view.retentionDeadline,
            operationID: operation.id, metadataBytes: first.frozenMetadataBytes, policy: view.metadata.read.policy)
        return first.attaching(reservation.map { [$0] } ?? [])
    }

}
#endif
