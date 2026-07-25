import Foundation
import SwiftData

/// Store reads used by duplicate display ID cleanup: resolving a scanned record
/// back to its live object and probing the committed `permanentDisplayId`.
///
/// Extracted from `DisplayIDMaintenanceService` to keep that type focused on the
/// scan/reassign flow. The used-display-ID snapshots that used to live here moved
/// to `UsedDisplayIDs`, which is shared with the other allocation call sites and
/// throws rather than swallowing a fetch failure (T-1621).
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
}
