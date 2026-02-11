import AppIntents
import Foundation
import SwiftData
@testable import Transit

struct TaskEntityQuery: EntityQuery {
    @Dependency
    private var projectService: ProjectService

    @MainActor
    func entities(for identifiers: [String]) async throws -> [TaskEntity] {
        let uuids = identifiers.compactMap { UUID(uuidString: $0) }

        // Fetch all tasks and filter in-memory (SwiftData predicate limitations with array contains)
        let descriptor = FetchDescriptor<TransitTask>()
        let allTasks = try projectService.context.fetch(descriptor)
        let matchingTasks = allTasks.filter { uuids.contains($0.id) }

        // Use compactMap to gracefully skip tasks without projects (CloudKit sync edge case)
        return matchingTasks.compactMap { try? TaskEntity.from($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskEntity] {
        // Return recent tasks for suggestion
        let descriptor = FetchDescriptor<TransitTask>(
            sortBy: [SortDescriptor(\.lastStatusChangeDate, order: .reverse)]
        )
        let tasks = try projectService.context.fetch(descriptor)

        // Use compactMap to gracefully skip tasks without projects (CloudKit sync edge case)
        return Array(tasks.prefix(10)).compactMap { try? TaskEntity.from($0) }
    }
}
