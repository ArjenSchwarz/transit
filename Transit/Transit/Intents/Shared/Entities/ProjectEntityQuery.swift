import AppIntents
import Foundation

struct ProjectEntityQuery: EntityQuery {
    @Dependency
    private var projectService: ProjectService

    @MainActor
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        Self.entities(for: identifiers, projectService: projectService)
    }

    @MainActor
    func suggestedEntities() async throws -> [ProjectEntity] {
        Self.suggestedEntities(projectService: projectService)
    }

    @MainActor
    static func entities(for identifiers: [String], projectService: ProjectService) -> [ProjectEntity] {
        if identifiers.isEmpty {
            return []
        }

        var wantedIDs = Set<UUID>()
        wantedIDs.reserveCapacity(identifiers.count)
        for identifier in identifiers {
            if let uuid = UUID(uuidString: identifier) {
                wantedIDs.insert(uuid)
            }
        }

        if wantedIDs.isEmpty {
            return []
        }

        let projects = (try? projectService.fetchAllProjects()) ?? []
        return projects.compactMap { project in
            guard wantedIDs.contains(project.id) else { return nil }
            return ProjectEntity.from(project)
        }
    }

    @MainActor
    static func suggestedEntities(projectService: ProjectService) -> [ProjectEntity] {
        let projects = (try? projectService.fetchAllProjects(sortedByName: true)) ?? []
        if projects.isEmpty {
            return []
        }

        var entities: [ProjectEntity] = []
        entities.reserveCapacity(projects.count)
        for project in projects {
            entities.append(ProjectEntity.from(project))
        }
        return entities
    }
}
