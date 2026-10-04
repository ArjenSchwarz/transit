import Foundation

/// Per-projection indices retain multiplicity instead of choosing arbitrary matches.
struct TaskLinkGraphIndex {
    var tasksById: [UUID: [TaskLinkTaskValue]] = [:]
    var edgesById: [UUID: [TaskLinkOccurrenceValue]] = [:]
    var incidence: [UUID: [TaskLinkOccurrenceValue]] = [:]
    var equivalents: [TaskLinkRelation: [TaskLinkOccurrenceValue]] = [:]
    var availableRemovals: [UUID: [TaskLinkRemovalValue]] = [:]
    var recognizedRemovals: [UUID: [TaskLinkRemovalValue]] = [:]
    var diagnostics: [TaskLinkDiagnostic] = []
    var invalidOccurrences: Set<Data> = []
    var retainedBytes = 0

    init(tasks: [TaskLinkTaskValue], occurrences: [TaskLinkOccurrenceValue], evidence: [TaskLinkRemovalValue],
         instant: Date, budget: TaskLinkGraphBudget) throws {
        try budget.check()
        for task in tasks {
            try budget.check()
            tasksById[task.id, default: []].append(task)
            retainedBytes += task.physicalKey.count + task.name.utf8.count + task.status.utf8.count + 16
            guard retainedBytes <= budget.maximumBytes else { throw TaskLinkGraphError.capacityExceeded }
        }
        for edge in occurrences {
            try budget.check()
            edgesById[edge.id, default: []].append(edge)
            incidence[edge.source, default: []].append(edge)
            if edge.target != edge.source { incidence[edge.target, default: []].append(edge) }
            equivalents[TaskLinkGraph.relation(edge), default: []].append(edge)
            retainedBytes += edge.physicalKey.count + edge.kind.utf8.count + 56
            guard retainedBytes <= budget.maximumBytes else { throw TaskLinkGraphError.capacityExceeded }
        }
        try recognize(evidence, instant: instant, budget: budget)
        guard retainedBytes <= budget.maximumBytes else { throw TaskLinkGraphError.capacityExceeded }
    }

    private mutating func recognize(
        _ evidence: [TaskLinkRemovalValue], instant: Date, budget: TaskLinkGraphBudget
    ) throws {
        var ids: [UUID: Int] = [:]
        for row in evidence { try budget.check(); ids[row.id, default: 0] += 1 }
        for row in evidence {
            try budget.check()
            retainedBytes += row.physicalKey.count + row.kind.utf8.count + row.occurrenceRevision.utf8.count + 88
            guard retainedBytes <= budget.maximumBytes else { throw TaskLinkGraphError.capacityExceeded }
            let elapsed = instant.timeIntervalSince(row.removedAt)
            let datesValid = elapsed.isFinite && elapsed >= 0
                && row.createdAt.timeIntervalSinceReferenceDate.isFinite && row.removedAt >= row.createdAt
            if datesValid, elapsed >= TaskLinkGraph.evidenceLifetime { continue }
            availableRemovals[row.edgeId, default: []].append(row)
            let original = TaskLinkOccurrenceValue(physicalKey: row.physicalKey, id: row.edgeId,
                kind: row.kind, source: row.source, target: row.target, createdAt: row.createdAt)
            let valid = ids[row.id] == 1 && elapsed.isFinite && elapsed >= 0
                && row.createdAt.timeIntervalSinceReferenceDate.isFinite && row.removedAt >= row.createdAt
                && row.source != row.target && TaskLinkGraph.storedKinds.contains(row.kind)
                && (try? TaskLinkGraph.occurrenceRevision(original)) == row.occurrenceRevision
            if valid { recognizedRemovals[row.edgeId, default: []].append(row) } else {
                diagnostics.append(TaskLinkDiagnostic(code: "invalid_removal_evidence",
                                                      taskIds: [row.source, row.target],
                                                      edgeId: row.edgeId, physicalKey: row.physicalKey))
            }
        }
    }

    mutating func diagnoseOccurrences(budget: TaskLinkGraphBudget) throws {
        for edges in edgesById.values {
            for edge in edges {
                try budget.check()
                diagnose(edge)
            }
        }
        for (id, matches) in tasksById where matches.count != 1 {
            try budget.check()
            diagnostics.append(TaskLinkDiagnostic(code: "ambiguous_endpoint", taskIds: [id],
                                                  edgeId: nil, physicalKey: Data()))
        }
        for (id, edges) in incidence {
            try budget.check()
            let duplicates = try edges.filter { try budget.check(); return $0.kind == "duplicate" && $0.source == id }
            if duplicates.count > 1 {
                for edge in duplicates { try budget.check(); add("duplicate_cardinality", edge: edge) }
            }
        }
    }

    private mutating func diagnose(_ edge: TaskLinkOccurrenceValue) {
        for id in [edge.source, edge.target] {
            if tasksById[id] == nil { add("missing_endpoint", edge: edge) } else if tasksById[id]?.count != 1 {
                add("ambiguous_endpoint", edge: edge)
            }
        }
        if edge.source == edge.target { add("self_link", edge: edge) }
        if !TaskLinkGraph.storedKinds.contains(edge.kind) { add("unknown_kind", edge: edge) }
        if !edge.createdAt.timeIntervalSinceReferenceDate.isFinite { add("malformed_date", edge: edge) }
        if edgesById[edge.id]?.count != 1 { add("occurrence_identity_collision", edge: edge) }
        if equivalents[TaskLinkGraph.relation(edge)]?.count != 1 {
            add("equivalent_occurrences", edge: edge)
        }
        if let removed = availableRemovals[edge.id], removed.contains(where: {
            $0.kind == edge.kind && $0.source == edge.source && $0.target == edge.target
                && $0.createdAt == edge.createdAt
        }) { add("active_removal_conflict", edge: edge) }
    }

    private mutating func add(_ code: String, edge: TaskLinkOccurrenceValue) {
        invalidOccurrences.insert(edge.physicalKey)
        diagnostics.append(TaskLinkDiagnostic(code: code, taskIds: [edge.source, edge.target],
                                              edgeId: edge.id, physicalKey: edge.physicalKey))
    }

    func assessment(
        id: UUID, matches: [TaskLinkTaskValue], cyclic: Set<UUID>, budget: TaskLinkGraphBudget
    ) throws -> TaskLinkBlockerAssessment {
        try budget.check()
        guard matches.count == 1, !cyclic.contains(id) else {
            return .invalid
        }
        var blocked = false
        for edge in incidence[id, default: []] {
            try budget.check()
            guard edge.kind == "dependency", edge.target == id else { continue }
            guard !invalidOccurrences.contains(edge.physicalKey), let source = tasksById[edge.source]?.first,
                  TaskLinkGraph.knownStatuses.contains(source.status) else { return .invalid }
            if source.status != "done" { blocked = true }
        }
        return blocked ? .blocked : .unblocked
    }
}
