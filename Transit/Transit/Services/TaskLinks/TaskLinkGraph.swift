import Foundation
import CryptoKit

/// Projects frozen values. No model access, saves, alias redirection or repair.
enum TaskLinkGraph {
    static let knownStatuses: Set<String> = [
        "idea", "planning", "spec", "ready-for-implementation", "in-progress", "ready-for-review", "done", "abandoned"
    ]

    static func occurrenceRevision(_ row: TaskLinkOccurrenceValue) throws -> String {
        let fields: [String: Any] = ["id": row.id.uuidString.lowercased(), "kind": row.kind,
            "source": row.source.uuidString.lowercased(), "target": row.target.uuidString.lowercased(),
            "createdAt": try MCPRecordRevision.exactDate(row.createdAt)]
        let canonical = try MCPCanonicalJSON.encode(fields)
        return "l1:" + SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func project(
        tasks: [TaskLinkTaskValue], occurrences: [TaskLinkOccurrenceValue],
        removalEvidence: [TaskLinkRemovalValue], evaluationInstant: Date,
        budget: TaskLinkGraphBudget = TaskLinkGraphBudget()
    ) throws -> TaskLinkGraphView {
        try budget.check()
        let taskIndex = Dictionary(grouping: tasks, by: \.id)
        let edgeIndex = Dictionary(grouping: occurrences, by: \.id)
        var incidence: [UUID: [TaskLinkOccurrenceValue]] = [:]
        var diagnostics: [TaskLinkDiagnostic] = []
        var retainedBytes = tasks.reduce(0) {
            $0 + $1.physicalKey.count + $1.name.utf8.count + $1.status.utf8.count + 16
        }
        for row in occurrences {
            try budget.check()
            retainedBytes += row.physicalKey.count + row.kind.utf8.count + 56
            incidence[row.source, default: []].append(row)
            if row.target != row.source { incidence[row.target, default: []].append(row) }
            func diagnose(_ code: String) {
                diagnostics.append(TaskLinkDiagnostic(code: code, taskIds: [row.source, row.target],
                    edgeId: row.id, physicalKey: row.physicalKey))
            }
            for endpoint in [row.source, row.target] {
                if taskIndex[endpoint] == nil {
                    diagnose("missing_endpoint")
                } else if taskIndex[endpoint]?.count != 1 { diagnose("ambiguous_endpoint") }
            }
            if row.source == row.target { diagnose("self_link") }
            if !["dependency", "association", "attribution", "duplicate"].contains(row.kind) {
                diagnose("unknown_kind")
            }
            if !row.createdAt.timeIntervalSinceReferenceDate.isFinite { diagnose("malformed_date") }
            if edgeIndex[row.id]?.count != 1 { diagnose("occurrence_identity_collision") }
        }
        retainedBytes += removalEvidence.reduce(0) {
            $0 + $1.physicalKey.count + $1.kind.utf8.count + $1.occurrenceRevision.utf8.count + 88
        }
        guard retainedBytes <= budget.maximumBytes else { throw TaskLinkGraphError.capacityExceeded }
        var blockers: [UUID: TaskLinkBlockerAssessment] = [:]
        for (id, matches) in taskIndex {
            try budget.check()
            guard matches.count == 1, knownStatuses.contains(matches[0].status) else {
                blockers[id] = .invalid; continue
            }
            let incoming = incidence[id, default: []].filter { $0.kind == "dependency" && $0.target == id }
            if incoming.contains(where: { edge in diagnostics.contains { $0.physicalKey == edge.physicalKey } }) {
                blockers[id] = .invalid
            } else if incoming.contains(where: { taskIndex[$0.source]?.first?.status != "done" }) {
                blockers[id] = .blocked
            } else { blockers[id] = .unblocked }
        }
        return TaskLinkGraphView(tasks: tasks, occurrences: occurrences, removalEvidence: removalEvidence,
            evaluationInstant: evaluationInstant, tasksById: taskIndex, occurrencesById: edgeIndex,
            incidence: incidence, diagnostics: diagnostics, cyclicTasks: [], blockers: blockers,
            retainedBytes: retainedBytes)
    }
}
