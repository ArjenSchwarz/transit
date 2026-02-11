import AppIntents
import Foundation

struct ProjectEntity: AppEntity {
    typealias DefaultQueryType = ProjectEntityQuery

    var id: String
    var projectId: UUID
    var name: String

    nonisolated static var defaultQuery: ProjectEntityQuery {
        ProjectEntityQuery()
    }

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Project")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static func from(_ project: Project) -> ProjectEntity {
        ProjectEntity(
            id: project.id.uuidString,
            projectId: project.id,
            name: project.name
        )
    }
}
