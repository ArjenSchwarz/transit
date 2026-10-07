import Foundation

/// Recorded graph observation; historical mappings never redirect a current write.
nonisolated struct TaskConsolidationMapping: Codable, Equatable, Sendable {
    let sourceTaskId: UUID
    let directTaskIds: [UUID]
    let canonicalTaskId: UUID?
    let path: [UUID]

    @MainActor static func capture(_ ids: [UUID], graph: TaskLinkGraphView, budget: TaskLinkGraphBudget) throws
        -> [Self] {
        try ids.map { id in
            try budget.check()
            let resolution = try TaskLinkGraph.duplicateResolution(for: id, in: graph, budget: budget)
            guard resolution.diagnostic == nil else { throw ConsolidationPlanningError.invalidCanonical }
            return Self(sourceTaskId: id, directTaskIds: graph.incidence[id, default: []]
                .filter { $0.kind == "duplicate" && $0.source == id }.map(\.target),
                canonicalTaskId: resolution.canonical, path: resolution.path)
        }
    }
}
