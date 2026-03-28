import AppIntents
import Foundation

struct TaskEntityQuery: EntityQuery {
    @Dependency
    private var taskService: TaskService

    @MainActor
    func entities(for identifiers: [String]) async throws -> [TaskEntity] {
        Self.entities(for: identifiers, taskService: taskService)
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskEntity] {
        Self.suggestedEntities(taskService: taskService)
    }

    @MainActor
    static func entities(for identifiers: [String], taskService: TaskService) -> [TaskEntity] {
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

        let tasks = (try? taskService.fetchAllTasks()) ?? []
        let matchingTasks = tasks.filter { wantedIDs.contains($0.id) }
        return entities(from: matchingTasks)
    }

    @MainActor
    static func suggestedEntities(taskService: TaskService) -> [TaskEntity] {
        let tasks = (try? taskService.fetchAllTasks()) ?? []
        if tasks.isEmpty {
            return []
        }

        let sorted = tasks.sorted { $0.lastStatusChangeDate > $1.lastStatusChangeDate }
        return entities(from: Array(sorted.prefix(10)))
    }

    static func entities(from tasks: [TransitTask]) -> [TaskEntity] {
        if tasks.isEmpty {
            return []
        }

        var entities: [TaskEntity] = []
        entities.reserveCapacity(tasks.count)
        for task in tasks {
            if let entity = try? TaskEntity.from(task) {
                entities.append(entity)
            }
        }
        return entities
    }
}
