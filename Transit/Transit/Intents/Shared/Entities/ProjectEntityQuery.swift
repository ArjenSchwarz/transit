import AppIntents
import Foundation

/// Narrow seam over project-list storage reads so EntityQuery tests can
/// deterministically distinguish a failed fetch from an empty database.
@MainActor
protocol ProjectFetching {
    func fetchAllProjects(sortedByName: Bool) throws -> [Project]
}

extension ProjectService: ProjectFetching {}

struct ProjectEntityQuery: EntityQuery {
    @Dependency
    private var projectService: ProjectService

    @MainActor
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        try Self.entities(for: identifiers, projectService: projectService)
    }

    @MainActor
    func suggestedEntities() async throws -> [ProjectEntity] {
        try Self.suggestedEntities(projectService: projectService)
    }

    @MainActor
    static func entities(
        for identifiers: [String],
        projectService: ProjectService,
        projectFetcher: (any ProjectFetching)? = nil
    ) throws -> [ProjectEntity] {
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

        let projects = try (projectFetcher ?? projectService).fetchAllProjects(sortedByName: false)
        return projects.compactMap { project in
            guard wantedIDs.contains(project.id) else { return nil }
            return ProjectEntity.from(project)
        }
    }

    @MainActor
    static func suggestedEntities(
        projectService: ProjectService,
        projectFetcher: (any ProjectFetching)? = nil
    ) throws -> [ProjectEntity] {
        let projects = try (projectFetcher ?? projectService).fetchAllProjects(sortedByName: true)
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
