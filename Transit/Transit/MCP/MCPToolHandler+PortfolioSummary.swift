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
                let pinned = try store.preparedResultView(for: snapshotID, now: retainedReadInstant(store))
                try MCPPortfolioReadEncoding.check(operation)
                return MCPPreparedToolRead(preparedResultPage: pinned.firstPage,
                    frozenMetadataBytes: pinned.root.frozenMetadataBytes, publications: [pinned.pin])
            case .continuation(let cursor, let policy):
                let pinned = try store.preparedResultPage(for: cursor, now: retainedReadInstant(store))
                try requireRetainedPolicy(policy, root: pinned.page.root)
                try MCPPortfolioReadEncoding.check(operation)
                return MCPPreparedToolRead(preparedResultPage: pinned.preparedPage,
                    frozenMetadataBytes: pinned.page.root.frozenMetadataBytes, publications: [pinned.pin])
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
        let reads = try pages.pages.map {
            try MCPPortfolioReadEncoding.check(operation)
            return try MCPPortfolioReadEncoding.prepared($0, metadata: capture.frozenMetadataBytes)
        }
        let owners = try MCPModernProviderBinding.prepareReadPages(reads,
            tool: "query_project_summaries", operation: operation)
        guard owners.count == reads.count, let firstOwner = owners.first, let first = reads.first else {
            throw MCPReadCaptureError.serializationFailure
        }
        let root = RetainedView(capture: capture.view, frozenMetadataBytes: capture.frozenMetadataBytes,
            window: window, initialRequest: request, firstPage: pages.pages[0], preparedResultPage: firstOwner)
        let captureBytes = try MCPPortfolioCaptureCharge.bytes(capture, operation: operation)
        let legacyBytes = try pages.pages.reduce(captureBytes) { total, bytes in
            try MCPPortfolioReadEncoding.check(operation)
            return try MCPResultRetentionAccounting.add(total, bytes.count)
        }
        let budget = try store.preparedResultBudget(originalCaptureIndexBytes: legacyBytes, operation: operation)
        let measured = try MCPResultPreparation.prepare(pages: owners, budget: budget,
            checkpoint: { try MCPPortfolioReadEncoding.check(operation) })
        let bundle = EncodedViewBundle(root: root, pages: Array(pages.pages.dropFirst()), cursors: pages.cursors,
            encodedCaptureByteCount: captureBytes, preparedResultBundle: measured)
        try MCPPortfolioReadEncoding.check(operation)
        let reservation = try store.reservePreparedCreate(bundle: bundle, preparedResults: measured,
            operation: operation, publicationDeadline: MCPPortfolioReadEncoding.publicationDeadline(operation))
        var attached = false
        defer { if !attached { try? store.rollback(reservation) } }
        let publication = try store.prepare(reservation: reservation)
        try MCPPortfolioReadEncoding.check(operation)
        attached = true
        return first.attachingPreparedResultPage(firstOwner).attaching([publication])
    }

    nonisolated func retainedReadInstant(_ store: MCPReusableSnapshotStore) -> ContinuousClock.Instant {
        store.domain.withLock { store.domain.currentInstantLocked }
    }

    nonisolated func requireRetainedPolicy(_ policy: MCPReadPolicy?, root: RetainedView) throws {
        if let policy, policy != root.capture.metadata.read.policy { throw MCPReusableSnapshotError.incompatible }
    }
}
#endif
