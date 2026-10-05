import Foundation
import SwiftData

/// Every incident physical occurrence participates, including malformed imports
/// and repeated identical tuples. Removal evidence and opposite labels do not.
@MainActor enum TaskLinkIncidence {
    static func capture(_ id: UUID, in context: ModelContext,
                        includePendingChanges: Bool = true) throws -> [TaskLinkOccurrenceValue] {
        var descriptor = FetchDescriptor<TaskLinkOccurrence>(predicate: #Predicate {
            $0.sourceTaskID == id || $0.targetTaskID == id
        })
        descriptor.includePendingChanges = includePendingChanges
        return try context.fetch(descriptor).map {
            TaskLinkOccurrenceValue(physicalKey: Data(), id: $0.id, kind: $0.kindRawValue,
                                    source: $0.sourceTaskID, target: $0.targetTaskID, createdAt: $0.createdAt)
        }
    }

    static func canonical(_ rows: [TaskLinkOccurrenceValue], incidentTo id: UUID,
                          budget: TaskLinkGraphBudget? = nil) throws -> [[String: Any]] {
        try budget?.check()
        let canonical = try rows.filter { row in
            try budget?.check()
            return row.source == id || row.target == id
        }.map { row in
            try budget?.check()
            let fields: [String: Any] = ["edgeId": MCPRecordRevision.uuid(row.id), "kind": row.kind,
                "sourceTaskId": MCPRecordRevision.uuid(row.source),
                "targetTaskId": MCPRecordRevision.uuid(row.target)]
            return (try MCPCanonicalJSON.encode(fields), fields)
        }.sorted { $0.0 < $1.0 }.map(\.1)
        try budget?.check()
        return canonical
    }
}
