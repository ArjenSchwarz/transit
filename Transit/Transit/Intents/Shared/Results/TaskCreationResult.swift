import AppIntents
import Foundation

struct TaskCreationResult: AppEntity {
    typealias DefaultQueryType = TaskCreationResultQuery

    var id: String
    var taskId: UUID
    var displayId: Int?
    var name: String
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
        // Title is the task name so Shortcuts/result UIs identify the task
        // that was just created. Project, display ID (when known) and status
        // are supporting context in the subtitle.
        let identifier = displayId.map { "T-\($0)" }
        let subtitleParts = [projectName, identifier, status.capitalized]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitleParts.joined(separator: " • "))"
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
            name: task.name,
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
