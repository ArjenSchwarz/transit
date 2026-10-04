#if os(macOS)
import Foundation

extension MCPToolHandler {
    nonisolated func handleSnapshotTaskQuery(
        request: MCPSnapshotTaskQueryRequest, operation: MCPReadOperation
    ) throws -> MCPPreparedToolRead {
        let cursorRequest: Bool
        if case .continuation = request { cursorRequest = true } else { cursorRequest = false }
        do {
            try MCPPortfolioReadEncoding.check(operation)
            let store = try reusableSnapshots.get()
            switch request {
            case .initial(let snapshotID, _, _, _, _):
                let pinned = try store.preparedResultView(for: snapshotID, now: retainedReadInstant(store))
                let plan = try MCPPortfolioProjection.query(root: pinned.root, request: request)
                try MCPPortfolioReadEncoding.check(operation)
                let reads = try ([plan.firstPage] + plan.pages).map {
                    try MCPPortfolioReadEncoding.check(operation)
                    return try MCPPortfolioReadEncoding.prepared($0, metadata: pinned.root.frozenMetadataBytes)
                }
                let owners = try MCPModernProviderBinding.prepareReadPages(reads,
                    tool: "query_tasks", operation: operation)
                guard owners.count == reads.count, let firstOwner = owners.first, let first = reads.first else {
                    throw MCPReadCaptureError.serializationFailure
                }
                let reservation = try store.reservePreparedAppend(snapshotID: snapshotID,
                    pages: plan.pages, cursors: plan.cursors, preparedPages: owners, operation: operation,
                    publicationDeadline: MCPPortfolioReadEncoding.publicationDeadline(operation))
                var attached = false
                defer { if !attached { try? store.rollback(reservation) } }
                _ = try store.prepare(reservation: reservation)
                // The original pin protects against same-ID root recreation during projection.
                let publication = MCPReusableSnapshotGuardedPublication(publicationStoreID: store.publicationStoreID,
                    domain: store.domain, pins: [pinned.pin], mutation: reservation.publication)
                try MCPPortfolioReadEncoding.check(operation)
                attached = true
                return first.attachingPreparedResultPage(firstOwner).attaching([publication])
            case .continuation(let cursor, let policy):
                let pinned = try store.preparedResultPage(for: cursor, now: retainedReadInstant(store))
                try requireRetainedPolicy(policy, root: pinned.page.root)
                let result = try MCPPortfolioReadEncoding.prepared(
                    pinned.page.encodedPage, metadata: pinned.page.root.frozenMetadataBytes)
                try MCPPortfolioReadEncoding.check(operation)
                return result.attachingPreparedResultPage(pinned.preparedPage).attaching([pinned.pin])
            }
        } catch {
            if let failure = try MCPPortfolioReadEncoding.normalized(error, cursor: cursorRequest) { return failure }
            throw error
        }
    }
}
#endif
