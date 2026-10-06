#if os(macOS)
import Foundation
import SwiftData
/// Synchronous revalidation inside the coordinator's clean owned commit context.
@MainActor final class ConsolidationRetainedReviewSource {
    private let container: ModelContainer
    private let store: MCPTaskQuerySnapshotStore
    private let originScopeId: String
    init(container: ModelContainer, store: MCPTaskQuerySnapshotStore, originScopeId: String) {
        self.container = container
        self.store = store
        self.originScopeId = originScopeId
    }
    func resolve(_ id: UUID, in context: ModelContext) throws -> TaskConsolidationOwnedReview {
        guard !context.hasChanges, !context.autosaveEnabled else {
            throw MCPWriteFailure("OUTCOME_UNCERTAIN", "Review resolution requires clean owned services")
        }
        let entry = try store.ownedReview(id: id, scope: originScopeId)
        guard ConsolidationReviewEntry.digest(entry.proposalBytes) == entry.integrityDigest,
              try ConsolidationReviewProposal.revision(entry.proposalBytes) == entry.revision else {
            throw MCPWriteFailure("CONSOLIDATION_REVIEW_UNAVAILABLE", "Retained proposal content is inconsistent")
        }
        let proposal = try ConsolidationReviewProposal.decode(entry.proposalBytes)
        guard (entry.kind == .apply) == (proposal.request != nil) else {
            throw MCPWriteFailure("CONSOLIDATION_REVIEW_UNAVAILABLE", "Retained proposal kind is inconsistent")
        }
        let budget = TaskLinkGraphBudget()
        let selection = try selection(proposal, context: context, budget: budget)
        let evidence = try TaskConsolidationSavedCapture(container: container).copy(selection,
            in: context, budget: budget)
        let current = try ConsolidationReviewProposal(request: proposal.request, operationId: proposal.operationId,
            evidence: evidence, budget: budget)
        let currentRevision = try ConsolidationReviewProposal.revision(
            current.encoded(budget: budget), budget: budget)
        guard currentRevision == entry.revision else {
            let ids = selection.selectedTaskIds
            let revisions = Dictionary(uniqueKeysWithValues: evidence.originals.filter { ids.contains($0.id) }
                .map { ($0.id.uuidString, $0.revision) })
            throw MCPWriteFailure("REVISION_CONFLICT", "Saved review dependencies changed",
                currentRevisions: revisions, affectedTaskIds: ids)
        }
        if let request = proposal.request {
            let plan = try ConsolidationPlanner.plan(request, originals: evidence.originals,
                graph: evidence.graph, budget: budget)
            return try TaskConsolidationOwnedReview.make(plan: plan, scope: originScopeId, id: id,
                revision: entry.revision)
        }
        guard let operationId = proposal.operationId else { throw ConsolidationPlanningError.invalidInput }
        let plan = try ConsolidationPlanner.undo(events: evidence.events.filter { $0.operationId == operationId },
            operationId: operationId, originals: evidence.originals, graph: evidence.graph, budget: budget)
        let ids = [plan.apply.survivorTaskId] + plan.apply.candidateTaskIds
        let revisions = Dictionary(uniqueKeysWithValues: evidence.originals.filter { ids.contains($0.id) }
            .map { ($0.id, $0.revision) })
        let payload = TaskConsolidationPayload(operationId: operationId, kind: "undo",
            survivorTaskId: plan.apply.survivorTaskId, candidateTaskIds: plan.apply.candidateTaskIds,
            reason: plan.apply.reason, preservationJSON: plan.apply.preservationJSON,
            changes: plan.changes.map(\.delta),
            appliedRevisions: Dictionary(uniqueKeysWithValues: revisions.map { ($0.key.uuidString, $0.value) }),
            createdOccurrences: [], retainedOccurrences: plan.apply.retainedOccurrences,
            removedOccurrences: plan.apply.createdOccurrences, requestKey: "preview", reviewId: id,
            reviewRevision: entry.revision, mappings: plan.apply.mappings)
        return TaskConsolidationOwnedReview(id: id, revision: entry.revision, originScopeId: originScopeId,
            payload: payload, changes: plan.changes, expectedRevisions: revisions, links: plan.links)
    }
    private func selection(_ proposal: ConsolidationReviewProposal, context: ModelContext,
                           budget: TaskLinkGraphBudget) throws -> ConsolidationCaptureSelection {
        if let request = proposal.request {
            return .init(selectedTaskIds: [request.survivorTaskId] + request.candidateTaskIds)
        }
        guard let operationId = proposal.operationId else { throw ConsolidationPlanningError.invalidInput }
        return try ConsolidationCaptureTarget.operation(operationId).resolve(in: context, budget: budget)
    }
}
#endif
