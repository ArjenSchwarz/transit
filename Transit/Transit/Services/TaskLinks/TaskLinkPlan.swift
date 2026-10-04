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
                    try registerEndpoint(row.source == source ? row.target : row.source,
                                         graph: savedGraph, affected: &affected, requireExisting: false)
                } else {
                    guard let rows = savedGraph.recognizedRemovals[edgeId], rows.count == 1,
                          let row = rows.first, row.source == source || row.target == source,
                          row.occurrenceRevision == revision else { throw TaskLinkGraphError.repairUnavailable }
                }
            case let .add(type, target):
                guard target != source else { throw TaskLinkGraphError.invalidGraph }
                let relation = type.normalized(source: source, target: target)
                let existing = savedGraph.incidence[source, default: []].filter {
                    TaskLinkGraph.relation($0) == relation
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
        let removedRelations = Set(removals.map(TaskLinkGraph.relation))
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
        return TaskLinkPlan(removals: removals, additions: additions, affectedEndpoints: affected)
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
