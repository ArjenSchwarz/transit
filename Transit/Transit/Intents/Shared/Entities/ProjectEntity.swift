import AppIntents
import Foundation

struct ProjectEntity: AppEntity {
    var id: String
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
