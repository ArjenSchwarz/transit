import Foundation
import SwiftData

@MainActor enum TaskLinkEvidenceMaintenance {
    /// Startup alone invokes maintenance; unit/UI memory hosts stay inactive.
    static func atStartup(container: ModelContainer, mode: AppPersistencePolicy.Mode,
                          persistence: PersistenceAvailability) {
        guard !mode.usesMemoryStore, !persistence.isFallbackStorageActive else { return }
        _ = try? cleanup(container: container, instant: Date(), limit: 128, budget: TaskLinkGraphBudget())
    }

    /// At most 512 candidates scanned and 128 deletions in one startup pass.
    /// Unsafe evidence remains untouched; this is not a remote sync safety horizon.
    static func cleanup(container: ModelContainer, instant: Date, limit: Int,
                        budget: TaskLinkGraphBudget) throws -> Int {
        try budget.check()
        guard instant.timeIntervalSinceReferenceDate.isFinite, (1...128).contains(limit) else {
            throw TaskLinkGraphError.invalidDelta
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let cutoff = instant.addingTimeInterval(-TaskLinkGraph.evidenceLifetime)
        var descriptor = FetchDescriptor<TaskLinkRemovalEvidence>(
            predicate: #Predicate { $0.removedAt <= cutoff }, sortBy: [SortDescriptor(\.removedAt)])
        descriptor.fetchLimit = min(512, limit * 4)
        descriptor.includePendingChanges = false
        let candidates = try context.fetch(descriptor)
        var removed = 0, bytes = 0
        do {
            for candidate in candidates {
                try budget.check()
                if removed == limit { break }
                bytes += candidate.kindRawValue.utf8.count + candidate.occurrenceRevision.utf8.count + 160
                guard bytes <= budget.maximumBytes else { throw TaskLinkGraphError.capacityExceeded }
                guard try eligible(candidate, instant: instant, budget: budget) else { continue }
                let id = candidate.id
                var exact = FetchDescriptor<TaskLinkRemovalEvidence>(predicate: #Predicate { $0.id == id })
                exact.fetchLimit = 2
                exact.includePendingChanges = false
                let rows = try context.fetch(exact)
                try budget.check()
                guard rows.count == 1, let fresh = rows.first,
                      fresh.persistentModelID == candidate.persistentModelID,
                      sameTuple(fresh, candidate), try eligible(fresh, instant: instant, budget: budget)
                else { continue }
                context.delete(fresh)
                removed += 1
            }
            try budget.check()
            if removed > 0 { try context.save() }
            return removed
        } catch {
            context.safeRollback()
            throw error
        }
    }

    private static func eligible(_ row: TaskLinkRemovalEvidence, instant: Date,
                                 budget: TaskLinkGraphBudget) throws -> Bool {
        try budget.check()
        let elapsed = instant.timeIntervalSince(row.removedAt)
        guard elapsed.isFinite, elapsed >= TaskLinkGraph.evidenceLifetime,
              row.createdAt.timeIntervalSinceReferenceDate.isFinite else { return false }
        let original = TaskLinkOccurrenceValue(physicalKey: Data(), id: row.edgeId, kind: row.kindRawValue,
            source: row.sourceTaskID, target: row.targetTaskID, createdAt: row.createdAt)
        return (try? TaskLinkGraph.occurrenceRevision(original)) == row.occurrenceRevision
    }

    private static func sameTuple(_ left: TaskLinkRemovalEvidence, _ right: TaskLinkRemovalEvidence) -> Bool {
        left.id == right.id && left.edgeId == right.edgeId && left.kindRawValue == right.kindRawValue
            && left.sourceTaskID == right.sourceTaskID && left.targetTaskID == right.targetTaskID
            && left.createdAt.timeIntervalSinceReferenceDate.bitPattern
                == right.createdAt.timeIntervalSinceReferenceDate.bitPattern
            && left.removedAt.timeIntervalSinceReferenceDate.bitPattern
                == right.removedAt.timeIntervalSinceReferenceDate.bitPattern
            && left.occurrenceRevision == right.occurrenceRevision
    }
}
