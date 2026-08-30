import Foundation
import SwiftData

/// Validates that a project remains usable at a creation persistence boundary.
///
/// The live context preserves pending inserts and deletes, while a transient
/// context observes peer-committed deletion even when the live context still
/// has a stale registered object. Fetch failures propagate so creation fails
/// closed rather than treating unreadable storage as a missing project.
enum CreationProjectValidator {
    static func validate<E: Error>(
        _ project: Project,
        in modelContext: ModelContext,
        error: @autoclosure () -> E
    ) throws {
        guard try exists(project, in: modelContext) else {
            throw error()
        }
    }

    private static func exists(
        _ project: Project,
        in modelContext: ModelContext
    ) throws -> Bool {
        let projectID = project.id

        if modelContext.deletedModelsArray.contains(where: {
            ($0 as? Project)?.id == projectID
        }) {
            return false
        }

        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectID }
        )
        guard try modelContext.fetch(descriptor).first != nil else {
            return false
        }

        if modelContext.insertedModelsArray.contains(where: {
            ($0 as? Project)?.id == projectID
        }) {
            return true
        }

        return try ModelContext(modelContext.container).fetch(descriptor).first != nil
    }
}
