#if os(macOS)
import Foundation
import SwiftData
extension TaskConsolidationService {
    func stagedGraph(_ before: TaskLinkGraphView, occurrences: [TaskLinkOccurrenceValue],
                     tasks: [UUID: TransitTask], instant: Date,
                     budget: TaskLinkGraphBudget) throws -> TaskLinkGraphView {
        let values = before.tasks.map { value in
            TaskLinkTaskValue(physicalKey: value.physicalKey, id: value.id, name: value.name,
                status: tasks[value.id]?.statusRawValue ?? value.status)
        }
        return try TaskLinkGraph.project(tasks: values, occurrences: occurrences,
            removalEvidence: before.removalEvidence, evaluationInstant: instant, budget: budget)
    }
    func result(_ history: ConsolidationHistoryProjection, snapshots: [MCPRecordSnapshot],
                graph: TaskLinkGraphView, budget: TaskLinkGraphBudget) throws -> [String: Any] {
        let ids = [history.apply.survivorTaskId] + history.apply.candidateTaskIds
        let mappings = try TaskConsolidationMapping.capture(ids, graph: graph, budget: budget)
        var result: [String: Any] = ["entityId": history.operationId.uuidString,
            "operationId": history.operationId.uuidString, "operationRevision": history.operationRevision,
            "reason": history.apply.reason, "participants": snapshots.map(\.record),
            "mappings": try JSONSerialization.jsonObject(with: JSONEncoder().encode(mappings)),
            "history": try JSONSerialization.jsonObject(with: JSONEncoder().encode(history)),
            "undoAvailable": history.undoAvailable]
        result["undoUnavailableReason"] = history.undoUnavailableReason
        result["reversalId"] = history.reversalId?.uuidString
        return result
    }
    struct ApplyPreflight {
        let command: MCPWriteCommand
        let operationId: UUID
        let changes: [TaskConsolidationReviewedTaskChange]
        let graph: TaskLinkGraphView
        let instant: Date
        let budget: TaskLinkGraphBudget
    }
    func preflightApply(_ review: TaskConsolidationOwnedReview, input: ApplyPreflight) throws {
        let command = input.command, operationId = input.operationId, changes = input.changes
        let graph = input.graph, instant = input.instant, budget = input.budget
        let placeholders = review.links.additions.map { addition in
            let id = UUID()
            return TaskLinkOccurrenceValue(physicalKey: Data(id.uuidString.utf8), id: id,
                kind: addition.relation.kind, source: addition.relation.source,
                target: addition.relation.target, createdAt: instant)
        }
        let projected = try TaskLinkGraph.project(tasks: graph.tasks,
            occurrences: graph.occurrences + placeholders, removalEvidence: graph.removalEvidence,
            evaluationInstant: instant, budget: budget)
        var candidate = try payload(review, effects: (operationId, changes), command: command,
            revisions: review.payload.appliedRevisions, created: placeholders.map(occurrence))
        candidate.mappings = try TaskConsolidationMapping.capture(
            [candidate.survivorTaskId] + candidate.candidateTaskIds, graph: projected, budget: budget)
        _ = try TaskConsolidationHistoryCodec.encode(candidate)
        try budget.check()
    }
}
#endif
