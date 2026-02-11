import AppIntents
import Foundation
import SwiftData

struct ProjectEntityQuery: EntityQuery {
    @Dependency
    private var projectService: ProjectService

    @MainActor
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        Self.entities(for: identifiers, modelContext: projectService.context)
    }

    @MainActor
    func suggestedEntities() async throws -> [ProjectEntity] {
        Self.suggestedEntities(modelContext: projectService.context)
    }

    @MainActor
    static func entities(for identifiers: [String], modelContext: ModelContext) -> [ProjectEntity] {
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

        let projects = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        return projects.compactMap { project in
            guard wantedIDs.contains(project.id) else { return nil }
            return ProjectEntity.from(project)
        }
    }

    @MainActor
    static func suggestedEntities(modelContext: ModelContext) -> [ProjectEntity] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\Project.name)]
        )
        let projects = (try? modelContext.fetch(descriptor)) ?? []
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
