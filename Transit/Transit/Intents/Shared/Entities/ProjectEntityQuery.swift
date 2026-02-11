import AppIntents
import Foundation
import SwiftData

struct ProjectEntityQuery: EntityQuery {
    @Dependency
    private var projectService: ProjectService

    @MainActor
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        let uuids = identifiers.compactMap { UUID(uuidString: $0) }
        let descriptor = FetchDescriptor<Project>()
        let allProjects = (try? projectService.context.fetch(descriptor)) ?? []
        return allProjects
            .filter { uuids.contains($0.id) }
            .map(ProjectEntity.from)
    }

    @MainActor
    func suggestedEntities() async throws -> [ProjectEntity] {
        let descriptor = FetchDescriptor<Project>()
        let allProjects = (try? projectService.context.fetch(descriptor)) ?? []
        return allProjects.map(ProjectEntity.from)
    }
}
