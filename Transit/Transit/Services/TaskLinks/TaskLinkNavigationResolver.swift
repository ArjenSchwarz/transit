import Foundation
import SwiftData

/// Extracted existing window resolution, before unique saved-navigation GREEN.
@MainActor enum TaskLinkNavigationResolver {
    static func resolve(_ id: UUID, in context: ModelContext) throws -> TransitTask? {
        var descriptor = FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
