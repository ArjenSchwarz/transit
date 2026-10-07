#if os(macOS)
import CryptoKit
import Foundation

/// Immutable server-side backing includes the entire saved dependency closure.
nonisolated struct ConsolidationReviewProposal: Codable, Sendable {
    let version: Int
    let request: ConsolidationRequest?
    let operationId: UUID?
    let originals: [ConsolidationOriginal]
    let events: [TaskConsolidationEventValue]
    let tasks: [TaskLinkTaskValue]
    let occurrences: [TaskLinkOccurrenceValue]
    let removals: [TaskLinkRemovalValue]
    let changes: [TaskConsolidationReviewedTaskChange]
    let plannedAdditions: [TaskLinkRelation]
    let plannedRemovals: [TaskLinkOccurrenceValue]
    let retainedOccurrences: [TaskConsolidationOccurrence]

    @MainActor init(request: ConsolidationRequest?, operationId: UUID?,
                    evidence: ConsolidationSavedEvidence, budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws {
        try budget.check()
        version = 1
        self.request = request
        self.operationId = operationId
        originals = evidence.originals
        events = evidence.events
        tasks = evidence.graph.tasks
        occurrences = evidence.graph.occurrences
        removals = evidence.graph.removalEvidence
        if let request {
            let plan = try ConsolidationPlanner.plan(request, originals: originals,
                graph: evidence.graph, budget: budget)
            changes = plan.changes
            plannedAdditions = plan.links.additions.map(\.relation)
            plannedRemovals = plan.links.removals
            retainedOccurrences = plan.retainedOccurrences
        } else if let operationId {
            let plan = try ConsolidationPlanner.undo(events: events.filter { $0.operationId == operationId },
                operationId: operationId, originals: originals, graph: evidence.graph, budget: budget)
            changes = plan.changes
            plannedAdditions = plan.links.additions.map(\.relation)
            plannedRemovals = plan.links.removals
            retainedOccurrences = plan.apply.retainedOccurrences
        } else { throw ConsolidationPlanningError.invalidInput }
        try budget.check()
    }

    func encoded(budget: TaskLinkGraphBudget? = nil) throws -> Data {
        try budget?.check()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(TaskConsolidationRawFields.exactDate(date))
        }
        let encoded = try encoder.encode(self)
        try budget?.check()
        let value = try JSONSerialization.jsonObject(with: encoded)
        let bytes = try JSONSerialization.data(withJSONObject: canonical(value, budget: budget), options: [.sortedKeys])
        try budget?.check()
        return bytes
    }

    func revision() throws -> String {
        try Self.revision(encoded())
    }
    static func decode(_ bytes: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try TaskConsolidationRawFields.date(decoder.singleValueContainer().decode(String.self))
        }
        let proposal = try decoder.decode(Self.self, from: bytes)
        guard proposal.version == 1, (proposal.request == nil) != (proposal.operationId == nil) else {
            throw ConsolidationPlanningError.unavailableEvidence
        }
        return proposal
    }

    /// Physical identity compares canonical JSON; scalar payload/raw metadata stay exact.
    private func canonical(_ value: Any, field: String? = nil, budget: TaskLinkGraphBudget? = nil) throws -> Any {
        try budget?.check()
        if let text = value as? String, ["physicalKey", "projectPhysicalKey"].contains(field),
           let bytes = Data(base64Encoded: text),
           let identity = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) {
            return try JSONSerialization.data(withJSONObject: identity,
                options: [.sortedKeys, .fragmentsAllowed]).base64EncodedString()
        }
        if let object = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, child) in object { result[key] = try canonical(child, field: key, budget: budget) }
            return result
        }
        if let values = value as? [Any] {
            let result = try values.map { try canonical($0, budget: budget) }
            let unordered: Set<String> = ["originals", "events", "tasks", "occurrences", "removals", "changes",
                "plannedAdditions", "plannedRemovals", "retainedOccurrences"]
            guard let field, unordered.contains(field) else { return result }
            return try result.map { value in
                (value, try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]))
            }.sorted { $0.1.lexicographicallyPrecedes($1.1) }.map(\.0)
        }
        return value
    }
}
#endif
