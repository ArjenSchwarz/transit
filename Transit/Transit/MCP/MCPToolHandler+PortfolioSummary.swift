#if os(macOS)
import Foundation

extension MCPToolHandler {
    nonisolated func handlePortfolioSummary(
        request: MCPPortfolioSummaryRequest, capture: MCPPreparedReadCapture?, operation: MCPReadOperation
    ) throws -> MCPPreparedToolRead {
        let cursorRequest: Bool
        if case .continuation = request { cursorRequest = true } else { cursorRequest = false }
        do {
            try MCPPortfolioReadEncoding.check(operation)
            let store = try reusableSnapshots.get()
            switch request {
            case .initial:
                guard let capture else { throw MCPReadCaptureError.incoherentCapture }
                return try preparePortfolioCapture(capture, request: request, store: store, operation: operation)
            case .replay(let snapshotID):
                let pinned = try store.preparedRetainedView(for: snapshotID, now: retainedReadInstant(store))
                let result = try MCPPortfolioReadEncoding.prepared(
                    pinned.root.firstPage, metadata: pinned.root.frozenMetadataBytes)
                try MCPPortfolioReadEncoding.check(operation)
                return result.attaching([pinned.pin])
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

    nonisolated private func preparePortfolioCapture(
        _ capture: MCPPreparedReadCapture, request: MCPPortfolioSummaryRequest,
        store: MCPReusableSnapshotStore, operation: MCPReadOperation
    ) throws -> MCPPreparedToolRead {
        guard case .initial(let window, let limit, _, _) = request else {
            throw MCPReadCaptureError.incoherentCapture
        }
        let summary = try PortfolioSummaryService.summarize(view: capture.view, window: window)
        try MCPPortfolioReadEncoding.check(operation)
        let pages = try MCPPortfolioReadEncoding.summaryPages(summary, view: capture.view, limit: limit,
                                                             operation: operation)
        let first = try MCPPortfolioReadEncoding.prepared(pages.pages[0], metadata: capture.frozenMetadataBytes)
        let root = RetainedView(capture: capture.view, frozenMetadataBytes: capture.frozenMetadataBytes,
                                window: window, initialRequest: request, firstPage: pages.pages[0])
        let bundle = EncodedViewBundle(root: root, pages: Array(pages.pages.dropFirst()), cursors: pages.cursors,
            encodedCaptureByteCount: try MCPPortfolioCaptureCharge.bytes(capture, operation: operation))
        try MCPPortfolioReadEncoding.check(operation)
        let reservation = try store.reserveCreate(bundle: bundle,
            publicationDeadline: MCPPortfolioReadEncoding.publicationDeadline(operation))
        var attached = false
        defer { if !attached { try? store.rollback(reservation) } }
        let publication = try store.prepare(reservation: reservation)
        try MCPPortfolioReadEncoding.check(operation)
        attached = true
        return first.attaching([publication])
    }

    nonisolated func retainedReadInstant(_ store: MCPReusableSnapshotStore) -> ContinuousClock.Instant {
        store.domain.withLock { store.domain.currentInstantLocked }
    }

    nonisolated func requireRetainedPolicy(_ policy: MCPReadPolicy?, root: RetainedView) throws {
        if let policy, policy != root.capture.metadata.read.policy { throw MCPReusableSnapshotError.incompatible }
    }
}
#endif
