import Foundation

nonisolated struct ConsolidationHistoryProjection: Codable, Equatable, Sendable {
    let operationId: UUID
    let operationRevision: String
    let apply: TaskConsolidationPayload
    let reversal: TaskConsolidationPayload?
    let reversalId: UUID?
    let undoAvailable: Bool
    let undoUnavailableReason: String?
}

extension ConsolidationHistoryProjection {
    @MainActor static func make(
        events: [TaskConsolidationEventValue], operationId: UUID,
        originals: [ConsolidationOriginal], graph: TaskLinkGraphView,
        budget: TaskLinkGraphBudget = TaskLinkGraphBudget()
    ) throws -> Self {
        let history = try TaskConsolidationHistoryCodec.history(events, operationId: operationId)
        let revision = try TaskConsolidationHistoryCodec.revision(events)
        var reason: String?
        if history.reversal != nil {
            reason = "already_reversed"
        } else {
            do {
                _ = try ConsolidationPlanner.undo(events: events, operationId: operationId,
                    originals: originals, graph: graph, budget: budget)
            } catch ConsolidationPlanningError.revisionConflict {
                reason = "REVISION_CONFLICT"
            } catch is TaskLinkGraphError {
                reason = "CONSOLIDATION_GRAPH_UNAVAILABLE"
            } catch {
                reason = "CONSOLIDATION_EVIDENCE_UNAVAILABLE"
            }
        }
        return Self(operationId: operationId, operationRevision: revision, apply: history.apply,
            reversal: history.reversal, reversalId: events.first { $0.kind == "undo" }?.id,
            undoAvailable: reason == nil, undoUnavailableReason: reason)
    }
}
