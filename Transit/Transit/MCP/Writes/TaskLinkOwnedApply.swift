#if os(macOS)
import Foundation
import SwiftData

@MainActor enum TaskLinkOwnedApply {
    struct Applied {
        let inserted: [TaskLinkOccurrenceValue]
        let removed: [TaskLinkOccurrenceValue]
    }

    /// Deletes only a freshly revalidated physical identity/immutable tuple.
    /// Evidence is a separate same-store insertion, never a platform tombstone.
    @discardableResult
    static func apply(_ plan: TaskLinkPlan, in context: ModelContext, instant: Date,
                      budget: TaskLinkGraphBudget) throws -> Applied {
        var inserted: [TaskLinkOccurrenceValue] = []
        for value in plan.removals {
            try budget.check()
            let id = value.id
            var descriptor = FetchDescriptor<TaskLinkOccurrence>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 2
            let rows = try context.fetch(descriptor)
            let identity = try JSONDecoder().decode(PersistentIdentifier.self, from: value.physicalKey)
            guard rows.count == 1, let row = rows.first, row.persistentModelID == identity,
                  row.kindRawValue == value.kind, row.sourceTaskID == value.source, row.targetTaskID == value.target,
                  sameDate(row.createdAt, value.createdAt)
            else { throw MCPWriteFailure("LINK_REPAIR_UNAVAILABLE", "Exact occurrence changed before owned deletion") }
            let evidenceID = UUID()
            guard try context.fetchCount(FetchDescriptor<TaskLinkRemovalEvidence>(predicate: #Predicate {
                $0.id == evidenceID
            })) == 0 else { throw MCPWriteFailure("DUPLICATE_TASK_IDENTIFIER", "New removal identity conflicts") }
            let evidence = TaskLinkRemovalEvidence(id: evidenceID, edgeId: value.id, kindRawValue: value.kind,
                sourceTaskID: value.source, targetTaskID: value.target, createdAt: value.createdAt,
                occurrenceRevision: try TaskLinkGraph.occurrenceRevision(value), removedAt: instant)
            context.delete(row)
            context.insert(evidence)
        }
        for addition in plan.additions {
            try budget.check()
            let id = UUID()
            let existing = try context.fetchCount(
                FetchDescriptor<TaskLinkOccurrence>(predicate: #Predicate { $0.id == id }))
            guard existing == 0
            else { throw MCPWriteFailure("DUPLICATE_TASK_IDENTIFIER", "New occurrence identity conflicts") }
            let occurrence = TaskLinkOccurrence(id: id, kindRawValue: addition.relation.kind,
                sourceTaskID: addition.relation.source, targetTaskID: addition.relation.target, createdAt: instant)
            context.insert(occurrence)
            inserted.append(TaskLinkOccurrenceValue(physicalKey: try JSONEncoder().encode(occurrence.persistentModelID),
                id: id, kind: occurrence.kindRawValue, source: occurrence.sourceTaskID,
                target: occurrence.targetTaskID, createdAt: occurrence.createdAt))
        }
        try budget.check()
        return Applied(inserted: inserted, removed: plan.removals)
    }

    private static func sameDate(_ left: Date, _ right: Date) -> Bool {
        left.timeIntervalSinceReferenceDate.bitPattern == right.timeIntervalSinceReferenceDate.bitPattern
    }
}
#endif
