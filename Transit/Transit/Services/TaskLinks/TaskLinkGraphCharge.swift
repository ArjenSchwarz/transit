import Foundation

/// Logical encoded backing bytes, including every retained index and derived value.
/// This follows the shared read retention contract; it is not a heap-size estimate.
nonisolated enum TaskLinkGraphCharge {
    static func bytes(_ view: TaskLinkGraphView, budget: TaskLinkGraphBudget) throws -> Int {
        try budget.check()
        var count = try encode(["evaluationInstant": bits(view.evaluationInstant), "tasks": [], "occurrences": [],
            "removalEvidence": [], "tasksById": [], "occurrencesById": [], "incidence": [],
            "recognizedRemovals": [], "diagnostics": [], "cyclicTasks": [],
            "invalidOccurrences": [], "blockers": []]).count
        try records(view.tasks, count: &count, budget: budget, value: task)
        try records(view.occurrences, count: &count, budget: budget, value: occurrence)
        try records(view.removalEvidence, count: &count, budget: budget, value: removal)
        try index(view.tasksById, count: &count, budget: budget, key: { $0.physicalKey })
        try index(view.occurrencesById, count: &count, budget: budget, key: { $0.physicalKey })
        try index(view.incidence, count: &count, budget: budget, key: { $0.physicalKey })
        try index(view.recognizedRemovals, count: &count, budget: budget, key: { $0.physicalKey })
        try records(view.diagnostics, count: &count, budget: budget) {
            ["code": $0.code, "taskIds": $0.taskIds.map(\.uuidString),
             "edgeId": $0.edgeId?.uuidString as Any? ?? NSNull(), "physicalKey": $0.physicalKey.base64EncodedString()]
        }
        for id in view.cyclicTasks {
            try budget.check(); try add(try encode(id.uuidString).count + 1, to: &count, budget)
        }
        for key in view.invalidOccurrences {
            try budget.check(); try add(try encode(key.base64EncodedString()).count + 1, to: &count, budget)
        }
        for (id, assessment) in view.blockers {
            try budget.check()
            try add(try encode([id.uuidString, assessment.rawValue]).count + 1, to: &count, budget)
        }
        try budget.check()
        return count
    }

    private static func records<Value>(
        _ values: [Value], count: inout Int, budget: TaskLinkGraphBudget, value: (Value) -> [String: Any]
    ) throws {
        try add(values.count + 2, to: &count, budget)
        for row in values { try budget.check(); try add(try encode(value(row)).count, to: &count, budget) }
    }

    private static func index<Value>(
        _ index: [UUID: [Value]], count: inout Int, budget: TaskLinkGraphBudget, key: (Value) -> Data
    ) throws {
        try add(index.count + 2, to: &count, budget)
        for (id, rows) in index {
            try budget.check()
            var keys: [String] = []
            for row in rows { try budget.check(); keys.append(key(row).base64EncodedString()) }
            try add(try encode(["id": id.uuidString, "physicalKeys": keys]).count, to: &count, budget)
        }
    }

    private static func add(_ bytes: Int, to count: inout Int, _ budget: TaskLinkGraphBudget) throws {
        let (sum, overflow) = count.addingReportingOverflow(bytes)
        guard !overflow, sum <= budget.maximumBytes else { throw TaskLinkGraphError.capacityExceeded }
        count = sum
    }

    private static func encode(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
    }

    /// Raw date bits retain even malformed imports without silently converting them to null/default dates.
    private static func bits(_ date: Date) -> String {
        String(date.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
    }

    private static func task(_ row: TaskLinkTaskValue) -> [String: Any] {
        ["physicalKey": row.physicalKey.base64EncodedString(), "id": row.id.uuidString,
         "name": row.name, "status": row.status]
    }

    private static func occurrence(_ row: TaskLinkOccurrenceValue) -> [String: Any] {
        ["physicalKey": row.physicalKey.base64EncodedString(), "id": row.id.uuidString, "kind": row.kind,
         "source": row.source.uuidString, "target": row.target.uuidString, "createdAt": bits(row.createdAt)]
    }

    private static func removal(_ row: TaskLinkRemovalValue) -> [String: Any] {
        ["physicalKey": row.physicalKey.base64EncodedString(), "id": row.id.uuidString, "edgeId": row.edgeId.uuidString,
         "kind": row.kind, "source": row.source.uuidString, "target": row.target.uuidString,
         "createdAt": bits(row.createdAt), "occurrenceRevision": row.occurrenceRevision,
         "removedAt": bits(row.removedAt)]
    }
}
