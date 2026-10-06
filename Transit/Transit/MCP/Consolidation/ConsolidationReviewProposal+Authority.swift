#if os(macOS)
import CryptoKit
import Foundation
extension ConsolidationReviewProposal {
    /// p1 covers reviewed authority. Full graph backing stays retained and independently checked,
    /// but unrelated names/statuses are not concurrency preconditions.
    nonisolated static func revision(_ bytes: Data, budget: TaskLinkGraphBudget? = nil) throws -> String {
        try budget?.check()
        let proposal = try decode(bytes)
        guard var authority = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw ConsolidationPlanningError.unavailableEvidence
        }
        let originals = Set(proposal.originals.map(\.id))
        let incident = proposal.occurrences.filter { originals.contains($0.source) || originals.contains($0.target) }
        let endpoints = Set(incident.flatMap { [$0.source, $0.target] }).union(originals)
        let statusDependencies = Set(incident.filter { $0.kind == "dependency" }
            .flatMap { [$0.source, $0.target] }).union(originals)
        let taskValues = try requireTasks(authority)
        authority["tasks"] = try taskValues.compactMap { task -> [String: Any]? in
            try budget?.check()
            guard let text = task["id"] as? String, let id = UUID(uuidString: text), endpoints.contains(id) else {
                return nil
            }
            var value = task
            value.removeValue(forKey: "name")
            if !statusDependencies.contains(id) { value.removeValue(forKey: "status") }
            return value
        }
        authority["occurrences"] = try occurrenceValues(authority, field: "occurrences", ids: originals, budget: budget)
        authority["removals"] = try occurrenceValues(authority, field: "removals", ids: originals, budget: budget)
        authority["authorityVersion"] = 1
        try budget?.check()
        let encoded = try JSONSerialization.data(withJSONObject: authority, options: [.sortedKeys])
        try budget?.check()
        return "p1:" + SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated private static func requireTasks(_ value: [String: Any]) throws -> [[String: Any]] {
        guard let tasks = value["tasks"] as? [[String: Any]] else {
            throw ConsolidationPlanningError.unavailableEvidence
        }
        return tasks
    }
    nonisolated private static func occurrenceValues(_ value: [String: Any], field: String, ids: Set<UUID>,
                                                     budget: TaskLinkGraphBudget?) throws -> [[String: Any]] {
        guard let values = value[field] as? [[String: Any]] else {
            throw ConsolidationPlanningError.unavailableEvidence
        }
        return try values.filter { row in
            try budget?.check()
            guard let source = (row["source"] as? String).flatMap(UUID.init(uuidString:)),
                  let target = (row["target"] as? String).flatMap(UUID.init(uuidString:)) else {
                throw ConsolidationPlanningError.unavailableEvidence
            }
            return ids.contains(source) || ids.contains(target)
        }
    }
}
#endif
