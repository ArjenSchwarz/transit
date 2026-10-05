#if os(macOS)
import Foundation
import SwiftData

/// Retained immutable review input; execution resolves it anew in the owned phase.
struct TaskConsolidationOwnedReview {
    let id: UUID
    let revision: String
    let originScopeId: String
    let payload: TaskConsolidationPayload
    let expectedRevisions: [UUID: String]
    let links: TaskLinkPlan
}

/// No save or receipt lifecycle here: the existing protected coordinator owns both.
@MainActor final class TaskConsolidationService {
    struct Configuration {
        let originScopeId: String
        let reviewSource: ReviewSource
        let clock: @MainActor () -> Date

        init(originScopeId: String, reviewSource: @escaping ReviewSource,
             clock: @escaping @MainActor () -> Date = Date.init) {
            self.originScopeId = originScopeId
            self.reviewSource = reviewSource
            self.clock = clock
        }
    }

    typealias ReviewSource = @MainActor (UUID, ModelContext) throws -> TaskConsolidationOwnedReview
    private let context: ModelContext
    private let originScopeId: String
    private let reviewSource: ReviewSource
    private let clock: @MainActor () -> Date

    init(context: ModelContext, originScopeId: String, reviewSource: @escaping ReviewSource,
         clock: @escaping @MainActor () -> Date = Date.init) {
        self.context = context
        self.originScopeId = originScopeId
        self.reviewSource = reviewSource
        self.clock = clock
    }

    func apply(_ command: MCPWriteCommand, reviewId: UUID) throws -> [String: Any] {
        guard command.tool == "consolidate_tasks" else {
            throw MCPWriteFailure("CONSOLIDATION_UNAVAILABLE", "Reversal capability is not yet installed")
        }
        guard !context.hasChanges, !context.autosaveEnabled else {
            throw MCPWriteFailure("OUTCOME_UNCERTAIN", "Consolidation needs a clean owned context")
        }
        let review = try reviewSource(reviewId, context)
        guard review.id == reviewId, review.revision == command.arguments["reviewRevision"] as? String,
              review.originScopeId == originScopeId, review.payload.kind == "apply",
              IntentHelpers.parseBoolValue(command.arguments["preservationAcknowledged"]) == true else {
            throw MCPWriteFailure("CONSOLIDATION_UNAVAILABLE", "Exact acknowledged local review is unavailable")
        }
        let budget = TaskLinkGraphBudget()
        let instant = clock()
        let tasks = try resolve(review, budget: budget)
        let graph = try TaskLinkService.graph(in: context, evaluationInstant: instant, budget: budget)
        for id in tasks.keys {
            try TaskLinkPlan.validateProposed(review.links, source: id, graph: graph, budget: budget)
        }
        let operationId = UUID()
        var collision = FetchDescriptor<TaskConsolidationEvent>(predicate: #Predicate {
            $0.id == operationId || $0.operationId == operationId
        })
        collision.fetchLimit = 1
        guard try context.fetch(collision).isEmpty else {
            throw MCPWriteFailure("CONSOLIDATION_UNAVAILABLE", "New operation identity conflicts")
        }
        let changes = try actualChanges(review.payload.changes, tasks: tasks,
            survivorId: review.payload.survivorTaskId, instant: instant)
        let prospective = try review.links.additions.map { addition in
            try occurrence(TaskLinkOccurrenceValue(physicalKey: Data(), id: UUID(), kind: addition.relation.kind,
                source: addition.relation.source, target: addition.relation.target, createdAt: instant))
        }
        // All UUIDs/tokens have fixed encoded lengths. This is the exact payload
        // charge before effects; actual allocated tuples replace placeholders.
        _ = try TaskConsolidationHistoryCodec.encode(payload(review, effects: (operationId, changes),
            command: command, revisions: review.payload.appliedRevisions, created: prospective))
        for change in changes {
            let task = tasks[change.taskId]!
            task.taskDescription = change.after.description
            task.metadataJSON = change.after.metadataJSON
            if task.statusRawValue != change.after.statusRawValue {
                StatusEngine.applyTransition(task: task, to: .abandoned, now: instant)
            }
        }
        let applied = try TaskLinkOwnedApply.apply(review.links, in: context, instant: instant, budget: budget)
        return try stage(OwnedEffects(id: operationId, changes: changes, applied: applied, graph: graph,
            instant: instant), review: review, command: command, tasks: tasks, budget: budget)
    }

    private struct OwnedEffects {
        let id: UUID
        let changes: [TaskConsolidationTaskChange]
        let applied: TaskLinkOwnedApply.Applied
        let graph: TaskLinkGraphView
        let instant: Date
    }

    private func stage(_ effects: OwnedEffects, review: TaskConsolidationOwnedReview, command: MCPWriteCommand,
                       tasks: [UUID: TransitTask], budget: TaskLinkGraphBudget) throws -> [String: Any] {
        let operationId = effects.id, changes = effects.changes, applied = effects.applied
        let graph = effects.graph, instant = effects.instant
        let removed = Set(applied.removed.map(\.id))
        let staged = graph.occurrences.filter { !removed.contains($0.id) } + applied.inserted
        let snapshots = try ([review.payload.survivorTaskId] + review.payload.candidateTaskIds).map { id in
            try MCPRecordSnapshot.task(tasks[id]!, incidence: staged, budget: budget) {
                try context.fetch(CommentService.descriptor(for: $0))
            }
        }
        let revisions = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entityID.uuidString, $0.revision) })
        let history = payload(review, effects: (operationId, changes), command: command,
            revisions: revisions, created: try applied.inserted.map(occurrence))
        let json = try TaskConsolidationHistoryCodec.encode(history)
        let event = TaskConsolidationEvent(id: operationId, operationId: operationId, kindRawValue: "apply",
            createdAt: instant, originScopeId: originScopeId, survivorTaskId: history.survivorTaskId,
            candidateTaskIds: history.candidateTaskIds, payloadJSON: json)
        context.insert(event)
        let value = try TaskConsolidationEventValue.capture(event)
        let revision = try TaskConsolidationHistoryCodec.revision([value])
        return ["entityId": operationId.uuidString, "operationId": operationId.uuidString,
            "operationRevision": revision, "reason": history.reason, "participants": snapshots.map(\.record),
            "undoAvailable": false, "undoUnavailableReason": "Reversal capability is not installed"]
    }

    private func resolve(_ review: TaskConsolidationOwnedReview, budget: TaskLinkGraphBudget)
        throws -> [UUID: TransitTask] {
        guard !context.hasChanges else {
            throw MCPWriteFailure("OUTCOME_UNCERTAIN", "Review resolution introduced pending changes")
        }
        try TaskConsolidationHistoryCodec.validate(review.payload)
        let ids = [review.payload.survivorTaskId] + review.payload.candidateTaskIds
        guard Set(review.expectedRevisions.keys) == Set(ids), review.links.removals.isEmpty else {
            throw MCPWriteFailure("CONSOLIDATION_UNAVAILABLE", "Incomplete group evidence")
        }
        var tasks: [UUID: TransitTask] = [:]
        for id in ids {
            try budget.check()
            var descriptor = FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 2
            descriptor.includePendingChanges = false
            let rows = try context.fetch(descriptor)
            guard rows.count == 1, let task = rows.first else {
                throw MCPWriteFailure("CONSOLIDATION_UNAVAILABLE", "Selected task is missing or ambiguous")
            }
            tasks[id] = task
        }
        let revisions = try Dictionary(uniqueKeysWithValues: ids.map {
            ($0.uuidString, try MCPRecordSnapshot.task(tasks[$0]!, in: context).revision)
        })
        guard ids.allSatisfy({ revisions[$0.uuidString] == review.expectedRevisions[$0] }) else {
            throw MCPWriteFailure("REVISION_CONFLICT", "Selected saved tasks changed since review",
                currentRevisions: revisions, affectedTaskIds: ids)
        }
        let survivor = tasks[review.payload.survivorTaskId]!
        guard let project = survivor.project else {
            throw MCPWriteFailure("CONSOLIDATION_UNAVAILABLE", "Common project is missing")
        }
        let projectId = project.id
        var projects = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
        projects.fetchLimit = 2
        projects.includePendingChanges = false
        let matches = try context.fetch(projects)
        guard matches.count == 1, matches[0].persistentModelID == project.persistentModelID,
              tasks.values.allSatisfy({ $0.project?.persistentModelID == project.persistentModelID }) else {
            throw MCPWriteFailure("CONSOLIDATION_UNAVAILABLE", "Common project identity is ambiguous or different")
        }
        return tasks
    }

    private func actualChanges(_ proposed: [TaskConsolidationTaskChange], tasks: [UUID: TransitTask],
                               survivorId: UUID, instant: Date) throws -> [TaskConsolidationTaskChange] {
        try proposed.map { change in
            let task = tasks[change.taskId]!
            guard try TaskConsolidationRawFields.capture(task) == change.before else {
                throw MCPWriteFailure("REVISION_CONFLICT", "Reviewed raw fields changed",
                    currentRevisions: [change.taskId.uuidString:
                        try MCPRecordSnapshot.task(task, in: context).revision],
                    affectedTaskIds: [change.taskId])
            }
            let statusChanges = change.before.statusRawValue != change.after.statusRawValue
            guard change.taskId == survivorId ? !statusChanges :
                    (change.before.description == change.after.description
                     && change.before.metadataJSON == change.after.metadataJSON),
                  statusChanges || (change.before.lastStatusChangeDate == change.after.lastStatusChangeDate
                     && change.before.completionDate == change.after.completionDate) else {
                throw MCPWriteFailure("CONSOLIDATION_UNAVAILABLE", "Review changes unsupported participant fields")
            }
            var after = change.after
            if change.before.statusRawValue != change.after.statusRawValue {
                guard let current = TaskStatus(rawValue: change.before.statusRawValue), !current.isTerminal,
                      change.after.statusRawValue == TaskStatus.abandoned.rawValue,
                      change.before.description == change.after.description,
                      change.before.metadataJSON == change.after.metadataJSON else {
                    throw MCPWriteFailure("CONSOLIDATION_UNAVAILABLE", "Unsupported reviewed status change")
                }
                after = TaskConsolidationRawFields(description: after.description, metadataJSON: after.metadataJSON,
                    statusRawValue: after.statusRawValue,
                    lastStatusChangeDate: try TaskConsolidationRawFields.exactDate(instant),
                    completionDate: try TaskConsolidationRawFields.exactDate(instant))
            }
            return TaskConsolidationTaskChange(taskId: change.taskId, before: change.before, after: after)
        }
    }

    private func payload(_ review: TaskConsolidationOwnedReview,
                         effects: (id: UUID, changes: [TaskConsolidationTaskChange]), command: MCPWriteCommand,
                         revisions: [String: String],
                         created: [TaskConsolidationOccurrence]) -> TaskConsolidationPayload {
        TaskConsolidationPayload(operationId: effects.id, kind: "apply", survivorTaskId: review.payload.survivorTaskId,
            candidateTaskIds: review.payload.candidateTaskIds, reason: review.payload.reason,
            preservationJSON: review.payload.preservationJSON, changes: effects.changes, appliedRevisions: revisions,
            createdOccurrences: created, retainedOccurrences: review.payload.retainedOccurrences,
            requestKey: command.key, reviewId: review.id, reviewRevision: review.revision)
    }

    private func occurrence(_ value: TaskLinkOccurrenceValue) throws -> TaskConsolidationOccurrence {
        TaskConsolidationOccurrence(id: value.id, kind: value.kind, source: value.source, target: value.target,
            createdAt: try TaskConsolidationRawFields.exactDate(value.createdAt),
            revision: try TaskLinkGraph.occurrenceRevision(value))
    }
}
#endif
