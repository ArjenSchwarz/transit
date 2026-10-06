#if os(macOS)
import Foundation
import SwiftData
extension TaskConsolidationService {
    func undo(_ command: MCPWriteCommand, reviewId: UUID) throws -> [String: Any] {
        guard !context.hasChanges, !context.autosaveEnabled,
              let raw = command.arguments["operationId"] as? String, let operationId = UUID(uuidString: raw) else {
            throw MCPWriteFailure("CONSOLIDATION_UNAVAILABLE", "A clean owned whole reversal is required")
        }
        let budget = TaskLinkGraphBudget()
        let events = try TaskConsolidationHistoryStore.savedEvents(operationId: operationId, in: context,
            budget: budget)
        let recorded = try TaskConsolidationHistoryCodec.history(events, operationId: operationId)
        if recorded.reversal != nil { return try alreadyReversed(events, operationId: operationId) }
        let review = try reviewSource(reviewId, context)
        guard review.id == reviewId, review.revision == command.arguments["reviewRevision"] as? String,
              review.originScopeId == originScopeId, review.payload.kind == "undo",
              review.payload.operationId == operationId else {
            throw MCPWriteFailure("CONSOLIDATION_REVIEW_UNAVAILABLE", "Exact local reversal review is unavailable")
        }
        let tasks = try resolve(review, budget: budget)
        let instant = clock()
        let graph = try TaskLinkService.graph(in: context, evaluationInstant: instant, budget: budget)
        let reversalId = UUID()
        guard try context.fetchCount(FetchDescriptor<TaskConsolidationEvent>(predicate: #Predicate {
            $0.id == reversalId
        })) == 0 else { throw TaskConsolidationHistoryError.ambiguous }
        try validateUndo(review, tasks: tasks, graph: graph, budget: budget)
        var payload = review.payload
        payload = undoPayload(payload, changes: review.changes, revisions: payload.appliedRevisions,
            command: command)
        _ = try TaskConsolidationHistoryCodec.encode(payload)
        for change in review.changes {
            let task = tasks[change.taskId]!
            task.taskDescription = change.after.description
            task.metadataJSON = change.after.metadataJSON
            task.statusRawValue = change.after.statusRawValue
            task.lastStatusChangeDate = try TaskConsolidationRawFields.date(change.after.lastStatusChangeDate)
            task.completionDate = try change.after.completionDate.map(TaskConsolidationRawFields.date)
        }
        let applied = try TaskLinkOwnedApply.apply(review.links, in: context, instant: instant, budget: budget)
        return try stageUndo(review, input: UndoStage(command: command, events: events, reversalId: reversalId,
            applied: applied, tasks: tasks, graph: graph, instant: instant, budget: budget))
    }
    private func validateUndo(_ review: TaskConsolidationOwnedReview, tasks: [UUID: TransitTask],
                              graph: TaskLinkGraphView, budget: TaskLinkGraphBudget) throws {
        for id in tasks.keys {
            try TaskLinkPlan.validateProposed(review.links, source: id, graph: graph, budget: budget)
        }
        for change in review.changes {
            guard let task = tasks[change.taskId], try TaskConsolidationRawFields.capture(task) == change.before else {
                throw MCPWriteFailure("CONSOLIDATION_UNAVAILABLE", "Whole reversal raw evidence changed")
            }
        }
    }
    private struct UndoStage {
        let command: MCPWriteCommand
        let events: [TaskConsolidationEventValue]
        let reversalId: UUID
        let applied: TaskLinkOwnedApply.Applied
        let tasks: [UUID: TransitTask]
        let graph: TaskLinkGraphView
        let instant: Date
        let budget: TaskLinkGraphBudget
    }
    private func stageUndo(_ review: TaskConsolidationOwnedReview, input: UndoStage) throws -> [String: Any] {
        let command = input.command, events = input.events, reversalId = input.reversalId, applied = input.applied
        let tasks = input.tasks, graph = input.graph, instant = input.instant, budget = input.budget
        let removed = Set(applied.removed.map(\.id))
        let occurrences = graph.occurrences.filter { !removed.contains($0.id) }
        let snapshots = try ([review.payload.survivorTaskId] + review.payload.candidateTaskIds).map { id in
            try MCPRecordSnapshot.task(tasks[id]!, incidence: occurrences, budget: budget) {
                try context.fetch(CommentService.descriptor(for: $0))
            }
        }
        let revisions = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entityID.uuidString, $0.revision) })
        let payload = undoPayload(review.payload, changes: review.changes, revisions: revisions, command: command)
        let event = TaskConsolidationEvent(id: reversalId, operationId: payload.operationId, kindRawValue: "undo",
            createdAt: instant, originScopeId: originScopeId, survivorTaskId: payload.survivorTaskId,
            candidateTaskIds: payload.candidateTaskIds, payloadJSON: try TaskConsolidationHistoryCodec.encode(payload))
        context.insert(event)
        let stagedEvents = try events + [TaskConsolidationEventValue.capture(event)]
        _ = try TaskConsolidationHistoryCodec.history(stagedEvents, operationId: payload.operationId)
        let savedGraph = try stagedGraph(graph, occurrences: occurrences, tasks: tasks, instant: instant,
            budget: budget)
        let history = try ConsolidationHistoryProjection.make(events: stagedEvents, operationId: payload.operationId,
            originals: [], graph: savedGraph, budget: budget)
        return try result(history, snapshots: snapshots, graph: savedGraph, budget: budget)
    }
    private func undoPayload(_ review: TaskConsolidationPayload, changes: [TaskConsolidationReviewedTaskChange],
                             revisions: [String: String], command: MCPWriteCommand) -> TaskConsolidationPayload {
        TaskConsolidationPayload(operationId: review.operationId, kind: "undo", survivorTaskId: review.survivorTaskId,
            candidateTaskIds: review.candidateTaskIds, reason: review.reason, preservationJSON: review.preservationJSON,
            changes: changes.map(\.delta), appliedRevisions: revisions, createdOccurrences: [],
            retainedOccurrences: review.retainedOccurrences, removedOccurrences: review.removedOccurrences,
            requestKey: command.key, reviewId: review.reviewId, reviewRevision: review.reviewRevision,
            mappings: review.mappings)
    }
    private func alreadyReversed(_ events: [TaskConsolidationEventValue], operationId: UUID) throws -> [String: Any] {
        let recorded = try TaskConsolidationHistoryCodec.history(events, operationId: operationId)
        guard let reversalId = events.first(where: { $0.kind == "undo" })?.id else {
            throw TaskConsolidationHistoryError.ambiguous
        }
        let revision = try TaskConsolidationHistoryCodec.revision(events)
        let history = ConsolidationHistoryProjection(operationId: operationId, operationRevision: revision,
            apply: recorded.apply, reversal: recorded.reversal, reversalId: reversalId,
            undoAvailable: false, undoUnavailableReason: "already_reversed")
        return ["entityId": operationId.uuidString, "operationId": operationId.uuidString,
            "operationRevision": revision, "reversalId": reversalId.uuidString, "reason": recorded.apply.reason,
            "alreadyReversed": true, "undoAvailable": false, "undoUnavailableReason": "already_reversed",
            "history": try JSONSerialization.jsonObject(with: JSONEncoder().encode(history))]
    }
}
#endif
