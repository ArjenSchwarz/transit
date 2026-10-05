import Foundation
import CryptoKit

/// Projects frozen values. No model access, saves, alias redirection or repair.
enum TaskLinkGraph {
    static let knownStatuses: Set<String> = [
        "idea", "planning", "spec", "ready-for-implementation", "in-progress", "ready-for-review", "done", "abandoned"
    ]
    static let storedKinds: Set<String> = ["dependency", "association", "attribution", "duplicate"]
    static let evidenceLifetime: TimeInterval = 7 * 24 * 60 * 60

    static func occurrenceRevision(_ row: TaskLinkOccurrenceValue) throws -> String {
        let fields: [String: Any] = ["id": row.id.uuidString.lowercased(), "kind": row.kind,
            "source": row.source.uuidString.lowercased(), "target": row.target.uuidString.lowercased(),
            "createdAt": try MCPRecordRevision.exactDate(row.createdAt)]
        let canonical = try MCPCanonicalJSON.encode(fields)
        return "l1:" + SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func relation(_ row: TaskLinkOccurrenceValue) -> TaskLinkRelation {
        if row.kind == "association" {
            return TaskLinkType.relatesTo.normalized(source: row.source, target: row.target)
        }
        return TaskLinkRelation(kind: row.kind, source: row.source, target: row.target)
    }

    static func project(
        tasks: [TaskLinkTaskValue], occurrences: [TaskLinkOccurrenceValue],
        removalEvidence: [TaskLinkRemovalValue], evaluationInstant: Date,
        budget: TaskLinkGraphBudget = TaskLinkGraphBudget()
    ) throws -> TaskLinkGraphView {
        var state = try TaskLinkGraphIndex(tasks: tasks, occurrences: occurrences,
                                          evidence: removalEvidence, instant: evaluationInstant, budget: budget)
        try state.diagnoseOccurrences(budget: budget)
        let cyclic = try cycleMembers(tasks: state.tasksById, occurrences: occurrences, budget: budget)
        for id in cyclic {
            try budget.check()
            state.diagnostics.append(TaskLinkDiagnostic(code: "dependency_cycle", taskIds: [id],
                                                        edgeId: nil, physicalKey: Data()))
        }
        let duplicateCycles = try cycleMembers(tasks: state.tasksById, occurrences: occurrences,
                                               kind: "duplicate", budget: budget)
        for id in duplicateCycles {
            try budget.check()
            state.diagnostics.append(TaskLinkDiagnostic(code: "duplicate_cycle", taskIds: [id],
                                                        edgeId: nil, physicalKey: Data()))
        }
        var blockers: [UUID: TaskLinkBlockerAssessment] = [:]
        for (id, matches) in state.tasksById {
            try budget.check()
            blockers[id] = try state.assessment(id: id, matches: matches, cyclic: cyclic, budget: budget)
        }
        try state.diagnostics.sort {
            try budget.check()
            let left = ($0.code, $0.taskIds.map(\.uuidString).joined(), $0.edgeId?.uuidString ?? "")
            let right = ($1.code, $1.taskIds.map(\.uuidString).joined(), $1.edgeId?.uuidString ?? "")
            return left == right ? $0.physicalKey.lexicographicallyPrecedes($1.physicalKey) : left < right
        }
        try budget.check()
        let view = TaskLinkGraphView(tasks: tasks, occurrences: occurrences, removalEvidence: removalEvidence,
            evaluationInstant: evaluationInstant, tasksById: state.tasksById, occurrencesById: state.edgesById,
            incidence: state.incidence, diagnostics: state.diagnostics, cyclicTasks: cyclic, blockers: blockers,
            retainedBytes: state.retainedBytes, invalidOccurrences: state.invalidOccurrences,
            recognizedRemovals: state.recognizedRemovals)
        return try view.withRetainedBytes(TaskLinkGraphCharge.bytes(view, budget: budget))
    }

    // Iterative Kosaraju. Every structurally resolvable physical dependency is retained.
    // Both traversals are iterative to bound stack use on large imported graphs.
    // swiftlint:disable:next cyclomatic_complexity
    static func cycleMembers(
        tasks: [UUID: [TaskLinkTaskValue]], occurrences: [TaskLinkOccurrenceValue],
        kind: String = "dependency", budget: TaskLinkGraphBudget
    ) throws -> Set<UUID> {
        var adjacency: [UUID: [UUID]] = [:], reverse: [UUID: [UUID]] = [:]
        for edge in occurrences {
            try budget.check()
            guard edge.kind == kind, tasks[edge.source]?.count == 1, tasks[edge.target]?.count == 1 else {
                continue
            }
            adjacency[edge.source, default: []].append(edge.target)
            reverse[edge.target, default: []].append(edge.source)
        }
        var visited: Set<UUID> = [], ordered: [UUID] = []
        for id in tasks.keys {
            try budget.check()
            guard visited.insert(id).inserted else { continue }
            var stack: [(UUID, Int)] = [(id, 0)]
            while let (node, offset) = stack.last {
                try budget.check()
                let neighbors = adjacency[node, default: []]
                if offset == neighbors.count { ordered.append(node); stack.removeLast(); continue }
                stack[stack.count - 1].1 += 1
                let next = neighbors[offset]
                if visited.insert(next).inserted { stack.append((next, 0)) }
            }
        }
        visited.removeAll(keepingCapacity: true)
        var cyclic: Set<UUID> = []
        for id in ordered.reversed() {
            try budget.check()
            guard visited.insert(id).inserted else { continue }
            var stack = [id], component: [UUID] = []
            while let node = stack.popLast() {
                try budget.check()
                component.append(node)
                for next in reverse[node, default: []] {
                    try budget.check()
                    if visited.insert(next).inserted { stack.append(next) }
                }
            }
            if component.count > 1 || adjacency[id, default: []].contains(id) { cyclic.formUnion(component) }
        }
        return cyclic
    }

    static func duplicateResolution(
        for id: UUID, in view: TaskLinkGraphView, budget: TaskLinkGraphBudget = TaskLinkGraphBudget()
    ) throws -> TaskLinkDuplicateResolution {
        var current = id, path: [UUID] = [], visited: Set<UUID> = []
        while true {
            try budget.check()
            guard visited.insert(current).inserted else {
                return TaskLinkDuplicateResolution(path: path + [current], canonical: nil,
                                                   diagnostic: "duplicate_cycle")
            }
            path.append(current)
            guard let matches = view.tasksById[current], matches.count == 1 else {
                return TaskLinkDuplicateResolution(path: path, canonical: nil,
                    diagnostic: view.tasksById[current] == nil ? "missing_endpoint" : "ambiguous_endpoint")
            }
            let edges = try view.incidence[current, default: []].filter {
                try budget.check(); return $0.kind == "duplicate" && $0.source == current
            }
            guard edges.count <= 1 else {
                return TaskLinkDuplicateResolution(path: path, canonical: nil, diagnostic: "duplicate_cardinality")
            }
            guard let edge = edges.first else {
                return TaskLinkDuplicateResolution(path: path, canonical: current, diagnostic: nil)
            }
            guard !view.invalidOccurrences.contains(edge.physicalKey) else {
                return TaskLinkDuplicateResolution(path: path, canonical: nil, diagnostic: "invalid_occurrence")
            }
            current = edge.target
        }
    }
}
