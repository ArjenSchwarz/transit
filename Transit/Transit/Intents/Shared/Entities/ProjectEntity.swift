import AppIntents
import Foundation

/// AppEntity wrapper for Project model, used in visual Shortcuts intents.
/// Provides project selection in Shortcuts UI via dropdown parameter.
struct ProjectEntity: AppEntity {
    var id: String  // UUID string representation for AppEntity conformance
    var projectId: UUID
    var name: String

    static var defaultQuery: ProjectEntityQuery { ProjectEntityQuery() }

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Project")
    }

    nonisolated var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    @MainActor
    static func from(_ project: Project) -> ProjectEntity {
        ProjectEntity(
            id: project.id.uuidString,
            projectId: project.id,
            name: project.name
        )
    }
}
