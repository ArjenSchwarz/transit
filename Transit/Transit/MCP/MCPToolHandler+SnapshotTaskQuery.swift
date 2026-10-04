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
                let pinned = try store.preparedRetainedView(for: snapshotID, now: retainedReadInstant(store))
                let plan = try MCPPortfolioProjection.query(root: pinned.root, request: request)
                try MCPPortfolioReadEncoding.check(operation)
                let first = try MCPPortfolioReadEncoding.prepared(
                    plan.firstPage, metadata: pinned.root.frozenMetadataBytes)
                if plan.pages.isEmpty { return first.attaching([pinned.pin]) }
                let reservation = try store.reserveAppend(
                    snapshotID: snapshotID, pages: plan.pages, cursors: plan.cursors,
                    publicationDeadline: MCPPortfolioReadEncoding.publicationDeadline(operation))
                var attached = false
                defer { if !attached { try? store.rollback(reservation) } }
                _ = try store.prepare(reservation: reservation)
                // The original pin protects against same-ID root recreation during projection.
                let publication = MCPReusableSnapshotGuardedPublication(publicationStoreID: store.publicationStoreID,
                    domain: store.domain, pins: [pinned.pin], mutation: reservation.publication)
                try MCPPortfolioReadEncoding.check(operation)
                attached = true
                return first.attaching([publication])
            case .continuation(let cursor, let policy):
                let pinned = try store.preparedPage(for: cursor, now: retainedReadInstant(store))
                try requireRetainedPolicy(policy, root: pinned.page.root)
                let result = try MCPPortfolioReadEncoding.prepared(
                    pinned.page.encodedPage, metadata: pinned.page.root.frozenMetadataBytes)
                try MCPPortfolioReadEncoding.check(operation)
                return result.attaching([pinned.pin])
            }
        } catch {
            if let failure = try MCPPortfolioReadEncoding.normalized(error, cursor: cursorRequest) { return failure }
            throw error
        }
    }
}
#endif
