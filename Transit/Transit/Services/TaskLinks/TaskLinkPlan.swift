import Foundation

nonisolated enum TaskLinkChange: Equatable, Sendable {
    case add(type: TaskLinkType, target: UUID)
    case remove(edgeId: UUID, occurrenceRevision: String)
}

nonisolated struct TaskLinkPlannedAddition: Equatable, Sendable {
    let relation: TaskLinkRelation
}

nonisolated struct TaskLinkPlan: Sendable {
    let removals: [TaskLinkOccurrenceValue]
    let additions: [TaskLinkPlannedAddition]
    let affectedEndpoints: Set<UUID>
    var isNoOp: Bool { removals.isEmpty && additions.isEmpty }
}

extension TaskLinkPlan {
    /// Reference/selector validation runs after replay/key acceptance. Source revision
    /// is enforced by the ordinary task command before applying this plan.
    @MainActor
    // Selector cases share one exact affected-endpoint accumulator.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func validate(
        delta: [TaskLinkChange], source: UUID, preconditions: [UUID: String],
        revisions: [UUID: String], savedGraph: TaskLinkGraphView,
        budget: TaskLinkGraphBudget = TaskLinkGraphBudget()
    ) throws -> TaskLinkPlan {
        guard delta.count <= 50 else { throw TaskLinkGraphError.invalidDelta }
        guard savedGraph.tasksById[source]?.count == 1 else { throw TaskLinkGraphError.missingSource }
        var removals: [TaskLinkOccurrenceValue] = [], additions: [TaskLinkPlannedAddition] = []
        var affected: Set<UUID> = [], selected: Set<UUID> = []
        var removedRelations: Set<TaskLinkRelation> = []
        for change in delta {
            try budget.check()
            switch change {
            case let .remove(edgeId, revision):
                guard selected.insert(edgeId).inserted else { throw TaskLinkGraphError.invalidDelta }
                if let rows = savedGraph.occurrencesById[edgeId] {
                    guard rows.count == 1, let row = rows.first, row.source == source || row.target == source,
                          try TaskLinkGraph.occurrenceRevision(row) == revision else {
                        throw TaskLinkGraphError.invalidOccurrence
                    }
                    removals.append(row)
                    removedRelations.insert(TaskLinkGraph.relation(row))
                    try registerEndpoint(row.source == source ? row.target : row.source,
                                         graph: savedGraph, affected: &affected, requireExisting: false)
                } else {
                    guard let rows = savedGraph.recognizedRemovals[edgeId], rows.count == 1,
                          let row = rows.first, row.source == source || row.target == source,
                          row.occurrenceRevision == revision else { throw TaskLinkGraphError.repairUnavailable }
                    removedRelations.insert(TaskLinkGraph.relation(TaskLinkOccurrenceValue(
                        physicalKey: row.physicalKey, id: row.edgeId, kind: row.kind, source: row.source,
                        target: row.target, createdAt: row.createdAt)))
                }
            case let .add(type, target):
                guard target != source else { throw TaskLinkGraphError.invalidGraph }
                let relation = type.normalized(source: source, target: target)
                let existing = try savedGraph.incidence[source, default: []].filter {
                    try budget.check()
                    return TaskLinkGraph.relation($0) == relation
                }
                if !existing.isEmpty {
                    guard existing.count == 1, let row = existing.first,
                          !savedGraph.invalidOccurrences.contains(row.physicalKey) else {
                        throw TaskLinkGraphError.invalidGraph
                    }
                    continue
                }
                guard !additions.contains(where: { $0.relation == relation }) else {
                    throw TaskLinkGraphError.invalidDelta
                }
                try registerEndpoint(target, graph: savedGraph, affected: &affected, requireExisting: true)
                additions.append(TaskLinkPlannedAddition(relation: relation))
            }
        }
        for change in delta {
            try budget.check()
            if case let .add(type, target) = change,
               removedRelations.contains(type.normalized(source: source, target: target)) {
                throw TaskLinkGraphError.invalidDelta
            }
        }
        guard Set(preconditions.keys) == affected else { throw TaskLinkGraphError.endpointPreconditions }
        for id in affected {
            try budget.check()
            guard let current = revisions[id], preconditions[id] == current else {
                throw TaskLinkGraphError.revisionConflict
            }
        }
        let plan = TaskLinkPlan(removals: removals, additions: additions, affectedEndpoints: affected)
        if delta.contains(where: { if case .add = $0 { true } else { false } }) {
            try validateProposed(plan, source: source, graph: savedGraph, budget: budget)
        }
        return plan
    }

    @MainActor
    private static func validateProposed(
        _ plan: TaskLinkPlan, source: UUID, graph: TaskLinkGraphView, budget: TaskLinkGraphBudget
    ) throws {
        let removed = Set(plan.removals.map(\.physicalKey))
        var rows = try graph.occurrences.filter { try budget.check(); return !removed.contains($0.physicalKey) }
        for addition in plan.additions {
            try budget.check()
            // Ephemeral validation identities never leave this pure proposed graph or enter the store.
            let id = UUID(), relation = addition.relation
            rows.append(TaskLinkOccurrenceValue(physicalKey: Data(id.uuidString.utf8), id: id,
                kind: relation.kind, source: relation.source, target: relation.target,
                createdAt: graph.evaluationInstant))
        }
        let proposed = try TaskLinkGraph.project(tasks: graph.tasks, occurrences: rows,
            removalEvidence: graph.removalEvidence, evaluationInstant: graph.evaluationInstant, budget: budget)
        let touched = plan.affectedEndpoints.union([source])
        for id in touched {
            try budget.check()
            guard proposed.assessment(for: id) != .invalid,
                  try TaskLinkGraph.duplicateResolution(for: id, in: proposed, budget: budget).diagnostic == nil else {
                throw TaskLinkGraphError.invalidGraph
            }
        }
        for diagnostic in proposed.diagnostics {
            try budget.check()
            // Unmatched malformed removal rows cannot authorize a retry; unrelated active incidence stays valid.
            if diagnostic.code != "invalid_removal_evidence", !Set(diagnostic.taskIds).isDisjoint(with: touched) {
                throw TaskLinkGraphError.invalidGraph
            }
        }
    }

    @MainActor
    private static func registerEndpoint(
        _ id: UUID, graph: TaskLinkGraphView, affected: inout Set<UUID>, requireExisting: Bool
    ) throws {
        guard let matches = graph.tasksById[id] else {
            if requireExisting { throw TaskLinkGraphError.invalidGraph }
            return
        }
        guard matches.count == 1 else { throw TaskLinkGraphError.ambiguousIdentity }
        affected.insert(id)
    }
}
