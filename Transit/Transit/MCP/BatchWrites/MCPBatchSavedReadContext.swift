#if os(macOS)
import Foundation
import SwiftData

/// Owns a private, non-saving context for one synchronous preview observation.
/// Fetch descriptors in preview validators must exclude pending changes; the
/// shared UI context is never fetched, refreshed, saved or rolled back here.
@MainActor enum MCPBatchSavedReadContext {
    static func withContext<Result>(
        container: ModelContainer, persistence: PersistenceAvailability,
        _ body: @MainActor (ModelContext) throws -> Result
    ) throws -> Result {
        guard !persistence.areWritesUnavailable else {
            throw MCPWriteFailure("PERSISTENCE_UNAVAILABLE", PersistenceAvailability.unavailableHint)
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try body(context)
    }
}
#endif
