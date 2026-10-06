import Foundation
import CryptoKit

enum ConsolidationPlanner {
    static func plan(_ request: ConsolidationRequest, originals: [ConsolidationOriginal],
                     graph: TaskLinkGraphView, budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws
        -> ConsolidationPlan {
        let selected = try select(request, originals: originals, graph: graph, budget: budget)
        let survivor = selected[0]
        let canonical = try TaskLinkGraph.duplicateResolution(for: survivor.id, in: graph, budget: budget)
        guard canonical.diagnostic == nil, canonical.canonical == survivor.id else {
            throw ConsolidationSelectionFailure(survivor.id, "survivor_not_canonical")
        }
        let changes = try proposedChanges(request, originals: selected)
        let links = try proposedLinks(request, graph: graph, budget: budget)
        for id in [request.survivorTaskId] + request.candidateTaskIds {
            try TaskLinkPlan.validateProposed(links.plan, source: id, graph: graph, budget: budget)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let accounting = String(data: try encoder.encode(request.preservation), encoding: .utf8) else {
            throw ConsolidationPlanningError.invalidInput
        }
        let payload = TaskConsolidationPayload(operationId: UUID(), kind: "apply",
            survivorTaskId: request.survivorTaskId, candidateTaskIds: request.candidateTaskIds,
            reason: request.reason, preservationJSON: accounting, changes: changes.map(\.delta),
            appliedRevisions: Dictionary(uniqueKeysWithValues: selected.map { ($0.id.uuidString, $0.revision) }),
            createdOccurrences: [], retainedOccurrences: links.retained, requestKey: "preview",
            reviewId: UUID(), reviewRevision: "p1:" + String(repeating: "0", count: 64))
        try TaskConsolidationHistoryCodec.validate(payload)
        let evidence = ConsolidationPlanDigest(request: request, originals: selected,
            changes: changes.map(\.delta), occurrences: try graph.occurrences.map(historyOccurrence))
        let bytes = try encoder.encode(evidence)
        guard bytes.count + graph.retainedBytes <= budget.maximumBytes
        else { throw TaskLinkGraphError.capacityExceeded }
        try budget.check()
        return ConsolidationPlan(request: request, originals: selected, changes: changes, links: links.plan,
            retainedOccurrences: links.retained,
            reviewRevision: "p1:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    }

    private static func select(_ request: ConsolidationRequest, originals: [ConsolidationOriginal],
                               graph: TaskLinkGraphView,
                               budget: TaskLinkGraphBudget) throws -> [ConsolidationOriginal] {
        let ids = [request.survivorTaskId] + request.candidateTaskIds
        guard (1...5).contains(request.candidateTaskIds.count), Set(ids).count == ids.count,
              !request.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConsolidationPlanningError.invalidInput
        }
        let selected = try ids.map { id in
            try budget.check()
            let matches = originals.filter { $0.id == id }
            guard matches.count == 1, graph.tasksById[id]?.count == 1 else {
                throw ConsolidationSelectionFailure(id, matches.isEmpty ? "missing_task" : "ambiguous_task")
            }
            guard let original = matches.first,
                  graph.tasksById[id]?.first?.physicalKey == original.physicalKey else {
                throw ConsolidationPlanningError.unavailableEvidence
            }
            try validate(original.fields)
            guard original.revision.range(of: "^r1:[0-9a-f]{64}$", options: .regularExpression)
                == original.revision.startIndex..<original.revision.endIndex else {
                throw ConsolidationPlanningError.unavailableEvidence
            }
            return original
        }
        guard let survivor = selected.first, selected.allSatisfy({ $0.projectId == survivor.projectId
            && $0.projectPhysicalKey == survivor.projectPhysicalKey }) else {
            let mismatch = selected.dropFirst().first { $0.projectId != selected[0].projectId
                || $0.projectPhysicalKey != selected[0].projectPhysicalKey }
            throw ConsolidationSelectionFailure(mismatch?.id ?? request.survivorTaskId, "wrong_project")
        }
        return selected
    }

    static func validate(_ fields: TaskConsolidationRawFields) throws {
        guard TaskStatus(rawValue: fields.statusRawValue) != nil
        else { throw ConsolidationPlanningError.unavailableEvidence }
        _ = try TaskConsolidationRawFields.date(fields.lastStatusChangeDate)
        if let date = fields.completionDate { _ = try TaskConsolidationRawFields.date(date) }
        if let raw = fields.metadataJSON {
            guard (try JSONSerialization.jsonObject(with: Data(raw.utf8))) is [String: String] else {
                throw ConsolidationPlanningError.unavailableEvidence
            }
        }
    }

    private static func proposedChanges(_ request: ConsolidationRequest, originals: [ConsolidationOriginal]) throws
        -> [TaskConsolidationReviewedTaskChange] {
        try originals.compactMap { original in
            let before = original.fields
            var description = before.description, metadata = before.metadataJSON, status = before.statusRawValue
            if original.id == request.survivorTaskId {
                if case let .replace(value) = request.survivorEdits.description { description = value }
                if let values = request.survivorEdits.metadata {
                    let bytes = try JSONSerialization.data(withJSONObject: values,
                        options: [.sortedKeys, .withoutEscapingSlashes])
                    guard let text = String(data: bytes, encoding: .utf8) else {
                        throw ConsolidationPlanningError.invalidInput
                    }
                    metadata = text
                }
            } else if let current = TaskStatus(rawValue: status), !current.isTerminal { status = "abandoned" }
            let after = TaskConsolidationRawFields(description: description, metadataJSON: metadata,
                statusRawValue: status,
                lastStatusChangeDate: before.lastStatusChangeDate, completionDate: before.completionDate)
            return after == before ? nil : .init(taskId: original.id, before: before, after: after)
        }
    }

    private struct PlannedLinks { let plan: TaskLinkPlan; let retained: [TaskConsolidationOccurrence] }

    private static func proposedLinks(_ request: ConsolidationRequest, graph: TaskLinkGraphView,
                                      budget: TaskLinkGraphBudget) throws -> PlannedLinks {
        var additions: [TaskLinkPlannedAddition] = [], retained: [UUID: TaskConsolidationOccurrence] = [:]
        for id in request.candidateTaskIds {
            let resolution = try TaskLinkGraph.duplicateResolution(for: id, in: graph, budget: budget)
            guard resolution.diagnostic == nil,
                resolution.canonical == id || resolution.canonical == request.survivorTaskId else {
                throw ConsolidationSelectionFailure(id, "invalid_canonical_chain")
            }
            if resolution.canonical == id {
                additions.append(.init(relation: TaskLinkType.duplicateOf.normalized(source: id,
                    target: request.survivorTaskId)))
            } else {
                for source in resolution.path.dropLast() {
                    let rows = graph.incidence[source,
                        default: []].filter { $0.kind == "duplicate" && $0.source == source }
                    guard rows.count == 1, let row = rows.first
                    else { throw ConsolidationPlanningError.unavailableEvidence }
                    retained[row.id] = try historyOccurrence(row)
                }
            }
        }
        return PlannedLinks(plan: TaskLinkPlan(removals: [], additions: additions,
            affectedEndpoints: Set([request.survivorTaskId] + request.candidateTaskIds)),
            retained: retained.values.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    static func historyOccurrence(_ value: TaskLinkOccurrenceValue) throws -> TaskConsolidationOccurrence {
        .init(id: value.id, kind: value.kind, source: value.source, target: value.target,
            createdAt: try TaskConsolidationRawFields.exactDate(value.createdAt),
            revision: try TaskLinkGraph.occurrenceRevision(value))
    }

    static func undo(events: [TaskConsolidationEventValue], operationId: UUID,
                     originals: [ConsolidationOriginal], graph: TaskLinkGraphView,
                     budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws -> ConsolidationReversalPlan {
        let history = try TaskConsolidationHistoryCodec.history(events, operationId: operationId)
        let revision = try TaskConsolidationHistoryCodec.revision(events)
        if history.reversal != nil {
            return .init(apply: history.apply, changes: [], links: .init(removals: [], additions: [],
                affectedEndpoints: []),
                operationRevision: revision, reversalId: events.first { $0.kind == "undo" }?.id)
        }
        let apply = history.apply, ids = [apply.survivorTaskId] + apply.candidateTaskIds
        let selected = try ids.map { id in
            let matches = originals.filter { $0.id == id }
            guard matches.count == 1, let original = matches.first, graph.tasksById[id]?.count == 1,
                  graph.tasksById[id]?.first?.physicalKey == original.physicalKey else {
                throw ConsolidationPlanningError.unavailableEvidence
            }
            try validate(original.fields)
            guard apply.appliedRevisions[id.uuidString] == original.revision else {
                throw ConsolidationPlanningError.revisionConflict
            }
            return original
        }
        let removals = try apply.createdOccurrences.map { try currentOccurrence($0, graph: graph) }
        for retained in apply.retainedOccurrences { _ = try currentOccurrence(retained, graph: graph) }
        let links = TaskLinkPlan(removals: removals, additions: [], affectedEndpoints: Set(ids))
        for id in ids { try TaskLinkPlan.validateProposed(links, source: id, graph: graph, budget: budget) }
        let changes = try apply.changes.map { delta in
            let original = selected.first { $0.id == delta.taskId }!
            let after = try restoring(delta.inverse, in: original.fields)
            return TaskConsolidationReviewedTaskChange(taskId: delta.taskId, before: original.fields, after: after)
        }
        return .init(apply: apply, changes: changes, links: links, operationRevision: revision, reversalId: nil)
    }

    private static func currentOccurrence(_ expected: TaskConsolidationOccurrence, graph: TaskLinkGraphView) throws
        -> TaskLinkOccurrenceValue {
        guard let rows = graph.occurrencesById[expected.id], rows.count == 1, let row = rows.first,
              !graph.invalidOccurrences.contains(row.physicalKey), try historyOccurrence(row) == expected else {
            throw ConsolidationPlanningError.unavailableEvidence
        }
        return row
    }

    static func restoring(_ delta: TaskConsolidationTaskChange, in fields: TaskConsolidationRawFields) throws
        -> TaskConsolidationRawFields {
        func value(_ key: String, current: String?) throws -> String? {
            guard let change = delta.fields[key] else { return current }
            guard change.before == current else { throw ConsolidationPlanningError.revisionConflict }
            return change.after
        }
        let description = try value("description", current: fields.description)
        let metadata = try value("metadataJSON", current: fields.metadataJSON)
        guard let status = try value("statusRawValue", current: fields.statusRawValue),
              let date = try value("lastStatusChangeDate", current: fields.lastStatusChangeDate) else {
            throw ConsolidationPlanningError.unavailableEvidence
        }
        return .init(description: description, metadataJSON: metadata, statusRawValue: status,
            lastStatusChangeDate: date, completionDate: try value("completionDate", current: fields.completionDate))
    }
}

private nonisolated struct ConsolidationPlanDigest: Encodable {
    let request: ConsolidationRequest
    let originals: [ConsolidationOriginal]
    let changes: [TaskConsolidationTaskChange]
    let occurrences: [TaskConsolidationOccurrence]
}
