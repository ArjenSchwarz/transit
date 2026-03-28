import AppIntents
import Foundation

struct TaskCreationResult: AppEntity {
    typealias DefaultQueryType = TaskCreationResultQuery

    var id: String
    var taskId: UUID
    var displayId: Int?
    var status: String
    var projectId: UUID
    var projectName: String

    nonisolated static var defaultQuery: TaskCreationResultQuery {
        TaskCreationResultQuery()
    }

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Created Task")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(projectName)",
            subtitle: "Task \(status)"
        )
    }

    static func from(_ task: TransitTask) throws -> TaskCreationResult {
        guard let project = task.project else {
            throw VisualIntentError.invalidInput(
                "Task has no associated project (data integrity issue)"
            )
        }

        return TaskCreationResult(
            id: task.id.uuidString,
            taskId: task.id,
            displayId: task.permanentDisplayId,
            status: task.statusRawValue,
            projectId: project.id,
            projectName: project.name
        )
    }
}

struct TaskCreationResultQuery: EntityQuery {
    @Dependency
    private var taskService: TaskService

    @MainActor
    func entities(for identifiers: [String]) async throws -> [TaskCreationResult] {
        Self.entities(for: identifiers, taskService: taskService)
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskCreationResult] {
        Self.suggestedEntities(taskService: taskService)
    }

    @MainActor
    static func entities(for identifiers: [String], taskService: TaskService) -> [TaskCreationResult] {
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
        var results: [TaskCreationResult] = []
        results.reserveCapacity(min(tasks.count, wantedIDs.count))

        for task in tasks {
            guard wantedIDs.contains(task.id) else { continue }
            if let result = try? TaskCreationResult.from(task) {
                results.append(result)
            }
        }

        return results
    }

    @MainActor
    static func suggestedEntities(taskService: TaskService) -> [TaskCreationResult] {
        let tasks = (try? taskService.fetchAllTasks()) ?? []
        if tasks.isEmpty {
            return []
        }

        let sorted = tasks.sorted { $0.creationDate > $1.creationDate }
        var results: [TaskCreationResult] = []
        results.reserveCapacity(min(sorted.count, 10))
        for task in sorted.prefix(10) {
            if let result = try? TaskCreationResult.from(task) {
                results.append(result)
            }
        }
        return results
    }
}
