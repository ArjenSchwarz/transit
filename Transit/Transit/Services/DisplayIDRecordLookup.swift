import Foundation
import SwiftData

/// Store reads used by duplicate display ID cleanup: resolving a scanned record
/// back to its live object, probing the committed `permanentDisplayId`, and
/// collecting the display IDs already in use.
///
/// Extracted from `DisplayIDMaintenanceService` to keep that type focused on the
/// scan/reassign flow.
struct DisplayIDRecordLookup {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Record resolution

    func task(id: UUID) -> TransitTask? {
        let descriptor = FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    func milestone(id: UUID) -> Milestone? {
        let descriptor = FetchDescriptor<Milestone>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Committed display ID probes

    /// Reads the task's committed `permanentDisplayId`. SwiftData has no
    /// per-object refresh, so a transient context is used to read the committed
    /// store value directly, bypassing the registered-object snapshot (T-1061).
    func storedTaskDisplayId(id: UUID) -> Int? {
        let descriptor = FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == id })
        let probe = ModelContext(modelContext.container)
        return (try? probe.fetch(descriptor).first)?.permanentDisplayId
    }

    /// Milestone companion to `storedTaskDisplayId` (T-1061).
    func storedMilestoneDisplayId(id: UUID) -> Int? {
        let descriptor = FetchDescriptor<Milestone>(predicate: #Predicate { $0.id == id })
        let probe = ModelContext(modelContext.container)
        return (try? probe.fetch(descriptor).first)?.permanentDisplayId
    }

    // MARK: - Used display IDs

    /// Permanent task display IDs already committed to the local store. Passed to
    /// `DisplayIDAllocator.allocateNextID(excluding:)` so a stale or stuck counter
    /// read cannot reissue an ID a record already holds (T-1766). Fetch failures
    /// degrade to an empty set so allocation still proceeds, matching the other
    /// allocation call sites (T-1621 tracks the swallowed error).
    func usedTaskDisplayIDs() -> Set<Int> {
        let descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.permanentDisplayId != nil }
        )
        guard let tasks = try? modelContext.fetch(descriptor) else { return [] }
        return Set(tasks.compactMap(\.permanentDisplayId))
    }

    /// Milestone companion to `usedTaskDisplayIDs` (T-1766).
    func usedMilestoneDisplayIDs() -> Set<Int> {
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.permanentDisplayId != nil }
        )
        guard let milestones = try? modelContext.fetch(descriptor) else { return [] }
        return Set(milestones.compactMap(\.permanentDisplayId))
    }
}
