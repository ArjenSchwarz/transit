#if os(macOS)
import Foundation

@MainActor final class MCPConsolidationPreviewAdapter {
    let service: MCPReadService
    let originScopeId: String

    init(service: MCPReadService, originScopeId: String) {
        self.service = service
        self.originScopeId = originScopeId
    }

    func prepare(tool: String, arguments: [String: Any], operation: MCPReadOperation) async throws
        -> MCPPreparedToolRead {
        operation.finishActorQueue()
        let request: ConsolidationRequest?
        let operationId: UUID?
        let policy: MCPReadPolicy
        let target: ConsolidationCaptureTarget
        switch tool {
        case "preview_task_consolidation":
            let parsed = try ConsolidationPreviewInput.apply(arguments)
            request = parsed.0
            operationId = nil
            policy = parsed.1
            target = .group([parsed.0.survivorTaskId] + parsed.0.candidateTaskIds)
        case "preview_task_consolidation_undo":
            let parsed = try ConsolidationPreviewInput.undo(arguments)
            request = nil
            operationId = parsed.0
            policy = parsed.1
            target = .operation(parsed.0)
        default: throw ConsolidationPlanningError.invalidInput
        }
        let capture = ReadCaptureRequest(projectSelectors: nil, selection: .tasks(detail: .fullRecord),
            completeness: .selectedRead, includeComments: true, consolidationTarget: target)
        let transform: MCPReadCaptureTransform = { @MainActor [self] capsule, operation in
            try prepare(capsule, tool: tool, request: request, operationId: operationId, operation: operation)
        }
        return try await service.prepareCapturedRead(request: capture, policy: policy,
            operation: operation, transform: transform)
    }

    private func prepare(_ capsule: MCPPreparedReadCapture, tool: String, request: ConsolidationRequest?,
                         operationId: UUID?, operation: MCPReadOperation) throws -> MCPPreparedToolRead {
        try MCPPortfolioReadEncoding.check(operation)
        guard let evidence = capsule.view.consolidationEvidence else {
            throw ConsolidationPlanningError.unavailableEvidence
        }
        let budget = TaskLinkGraphBudget(deadline: try MCPPortfolioReadEncoding.publicationDeadline(operation),
            checkpoint: { try MCPPortfolioReadEncoding.check(operation) })
        let bytes: Data
        if let request {
            bytes = try TaskConsolidationPreviewProjection.apply(request, evidence: evidence, budget: budget)
        } else if let operationId {
            bytes = try TaskConsolidationPreviewProjection.undo(operationId, evidence: evidence, budget: budget)
        } else { throw ConsolidationPlanningError.invalidInput }
        guard var result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw MCPReadCaptureError.serializationFailure
        }
        if result["undoAvailable"] as? Bool == false {
            return try MCPPreparedToolRead(text: service.jsonText(result),
                frozenMetadataBytes: capsule.frozenMetadataBytes)
        }
        try MCPPortfolioReadEncoding.check(operation)
        let proposal = try ConsolidationReviewProposal(request: request, operationId: operationId,
            evidence: evidence, budget: budget)
        let proposalBytes = try proposal.encoded(budget: budget)
        try MCPPortfolioReadEncoding.check(operation)
        let entry = ConsolidationReviewEntry(id: UUID(), kind: request == nil ? .undo : .apply,
            originScopeId: originScopeId, revision: ConsolidationReviewProposal.revision(proposalBytes),
            proposalBytes: proposalBytes,
            expiresAt: capsule.view.retentionDeadline)
        result["reviewId"] = entry.id.uuidString
        result["reviewRevision"] = entry.revision
        result["reviewExpiresAt"] = try expiry(capsule.view.metadata.asOf)
        let prepared = try MCPPreparedToolRead(text: service.jsonText(result),
            frozenMetadataBytes: capsule.frozenMetadataBytes)
        let owners = try service.preparePrivatePages([prepared], tool: tool, operation: operation)
            ?? MCPModernProviderBinding.prepareReadPages([prepared], tool: tool, operation: operation)
        guard owners.count == 1, let owner = owners.first else { throw MCPReadCaptureError.incoherentCapture }
        let accounting = try service.snapshots.domain.accounting(for: service.snapshots.publicationStoreID)
        let bundle = try MCPResultPreparation.prepare(pages: owners,
            budget: .init(store: .ordinary, originalCaptureIndexBytes: entry.retainedByteCount,
                visibleBytes: accounting.visibleBytes, pendingBytes: accounting.pendingBytes), checkpoint: {
                try MCPPortfolioReadEncoding.check(operation)
            })
        let deadline = try MCPPortfolioReadEncoding.publicationDeadline(operation)
        let reservation = try service.snapshots.prepareReview(entry, bundle: bundle,
            operationID: operation.id, deadline: deadline)
        return prepared.attachingPreparedResultPage(owner).attaching([reservation])
    }
    private func expiry(_ timestamp: String) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let asOf = formatter.date(from: timestamp) else { throw MCPReadCaptureError.incoherentCapture }
        return formatter.string(from: asOf.addingTimeInterval(300))
    }

}
#endif
