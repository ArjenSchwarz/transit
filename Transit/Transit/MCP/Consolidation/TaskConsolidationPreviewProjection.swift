#if os(macOS)
import Foundation

@MainActor enum TaskConsolidationPreviewProjection {
    static func apply(_ request: ConsolidationRequest, evidence: ConsolidationSavedEvidence,
                      budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws -> Data {
        try budget.check()
        let plan = try ConsolidationPlanner.plan(request, originals: evidence.originals,
            graph: evidence.graph, budget: budget)
        var result: [String: Any] = ["survivorTaskId": request.survivorTaskId.uuidString,
            "candidateTaskIds": request.candidateTaskIds.map(\.uuidString), "reason": request.reason,
            "preservation": try object(request.preservation), "survivorEdits": edits(request.survivorEdits),
            "originals": try originals(evidence, budget: budget), "changes": try object(plan.changes.map(\.delta)),
            "plannedLinks": ["additions": plan.links.additions.map { addition in
                ["kind": addition.relation.kind, "sourceTaskId": addition.relation.source.uuidString,
                 "targetTaskId": addition.relation.target.uuidString]
            }, "createdAt": "assigned_at_commit", "retainedOccurrences": try object(plan.retainedOccurrences)]]
        result["assignedAtCommit"] = plan.changes.filter {
            $0.before.statusRawValue != $0.after.statusRawValue
        }.map { ["taskId": $0.taskId.uuidString, "fields": ["lastStatusChangeDate", "completionDate"]] }
        try budget.check()
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        try budget.check()
        return bytes
    }

    static func undo(_ operationId: UUID, evidence: ConsolidationSavedEvidence,
                     budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws -> Data {
        try budget.check()
        let events = evidence.events.filter { $0.operationId == operationId }
        let history = try ConsolidationHistoryProjection.make(events: events, operationId: operationId,
            originals: evidence.originals, graph: evidence.graph, budget: budget)
        try budget.check()
        var result: [String: Any] = ["operationId": operationId.uuidString,
            "operationRevision": history.operationRevision, "reason": history.apply.reason,
            "preservation": try JSONSerialization.jsonObject(with: Data(history.apply.preservationJSON.utf8)),
            "changes": try object(history.apply.changes), "originals": try originals(evidence, budget: budget),
            "undoAvailable": history.undoAvailable, "history": try object(history)]
        if let reason = history.undoUnavailableReason { result["undoUnavailableReason"] = reason }
        if history.undoAvailable {
            let plan = try ConsolidationPlanner.undo(events: events, operationId: operationId,
                originals: evidence.originals, graph: evidence.graph, budget: budget)
            result["reversalChanges"] = try object(plan.changes.map(\.delta))
            result["removedOccurrences"] = try object(history.apply.createdOccurrences)
        }
        try budget.check()
        let bytes = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        try budget.check()
        return bytes
    }

    static func edits(_ value: ConsolidationEdits) -> [String: Any] {
        var result: [String: Any] = [:]
        if case .replace(let description) = value.description {
            result["description"] = description as Any? ?? NSNull()
        }
        if let metadata = value.metadata { result["metadata"] = metadata }
        return result
    }

    static func originals(_ evidence: ConsolidationSavedEvidence, budget: TaskLinkGraphBudget) throws
        -> [[String: Any]] {
        try evidence.originals.map { original in
            try budget.check()
            guard var record = try JSONSerialization.jsonObject(with: original.recordJSON) as? [String: Any] else {
                throw ConsolidationPlanningError.unavailableEvidence
            }
            let detail = try TaskLinkQueryProjection.detail(original.id, graph: evidence.graph, budget: budget)
            record.merge(detail) { _, saved in saved }
            record["taskId"] = original.id.uuidString
            record["revision"] = original.revision
            record["rawFields"] = try object(original.fields)
            record["consolidationHistory"] = try object(evidence.history.filter {
                $0.apply.survivorTaskId == original.id || $0.apply.candidateTaskIds.contains(original.id)
            })
            record["consolidationHistoryCoverage"] = "complete"
            try budget.check()
            return record
        }
    }

    static func object<Value: Encodable>(_ value: Value) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
    }
}
#endif
