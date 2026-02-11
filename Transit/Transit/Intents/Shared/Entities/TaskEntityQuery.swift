import AppIntents
import Foundation
import SwiftData

struct TaskEntityQuery: EntityQuery {
    @Dependency
    private var projectService: ProjectService

    @MainActor
    func entities(for identifiers: [String]) async throws -> [TaskEntity] {
        let uuids = identifiers.compactMap { UUID(uuidString: $0) }
        let descriptor = FetchDescriptor<TransitTask>()
        let allTasks = (try? projectService.context.fetch(descriptor)) ?? []
        let matchingTasks = allTasks.filter { uuids.contains($0.id) }
        return matchingTasks.compactMap { try? TaskEntity.from($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskEntity] {
        let descriptor = FetchDescriptor<TransitTask>(
            sortBy: [SortDescriptor(\.lastStatusChangeDate, order: .reverse)]
        )
        let tasks = (try? projectService.context.fetch(descriptor)) ?? []
        return Array(tasks.prefix(10)).compactMap { try? TaskEntity.from($0) }
    }
}
