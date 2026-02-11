import AppIntents
import Foundation
import SwiftData

/// EntityQuery for ProjectEntity, fetches available projects from SwiftData.
/// Returns empty array when no projects exist (graceful degradation).
struct ProjectEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        // Stub implementation - will be completed in task 4.3
        []
    }

    @MainActor
    func suggestedEntities() async throws -> [ProjectEntity] {
        // Stub implementation - will be completed in task 4.3
        []
    }
}
