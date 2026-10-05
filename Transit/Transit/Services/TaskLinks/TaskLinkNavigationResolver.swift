import Foundation
import SwiftData

/// Shared by click and window resolution. No first-match UUID navigation.
@MainActor enum TaskLinkNavigationResolver {
    static func resolve(_ id: UUID, in context: ModelContext) throws -> TransitTask? {
        let saved = ModelContext(context.container)
        saved.autosaveEnabled = false
        var descriptor = FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 2
        descriptor.includePendingChanges = false
        let matches = try saved.fetch(descriptor)
        guard matches.count == 1, let identity = matches.first?.persistentModelID else { return nil }
        // Return a model owned by the caller's retained navigation context.
        guard let task = context.model(for: identity) as? TransitTask, task.id == id, !task.isDeleted else {
            return nil
        }
        return task
    }
}
