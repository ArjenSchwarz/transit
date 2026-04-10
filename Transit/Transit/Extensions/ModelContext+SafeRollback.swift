import SwiftData

extension ModelContext {

    /// Performs a rollback and forces re-faulting of all `@Model` objects.
    ///
    /// Workaround for a SwiftData bug where `rollback()` clears dirty state
    /// (`hasChanges → false`) and reverts the persistent store, but does NOT
    /// re-fault `@Model` property accessors. In-memory properties retain their
    /// mutated values even though the store has been reverted.
    ///
    /// Performing a `fetch()` after `rollback()` forces SwiftData to re-fault
    /// every registered model, restoring in-memory properties to match the
    /// reverted store.
    ///
    /// - Note: If you add a new `@Model` entity, add a fetch for it here.
    func safeRollback() {
        rollback()
        refaultAllEntities()
    }

    /// Forces re-faulting of all registered `@Model` objects by fetching
    /// every entity type. The fetch results are discarded — only the
    /// re-faulting side effect matters.
    private func refaultAllEntities() {
        _ = try? fetch(FetchDescriptor<Project>())
        _ = try? fetch(FetchDescriptor<TransitTask>())
        _ = try? fetch(FetchDescriptor<Comment>())
        _ = try? fetch(FetchDescriptor<Milestone>())
        _ = try? fetch(FetchDescriptor<SyncHeartbeat>())
    }
}
