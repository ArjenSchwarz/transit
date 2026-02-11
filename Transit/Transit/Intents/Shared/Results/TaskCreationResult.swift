import AppIntents
import Foundation

/// A lightweight result returned by AddTaskIntent after creating a task.
/// Conforms to AppEntity so it can be used with `ReturnsValue<TaskCreationResult>`.
struct TaskCreationResult: AppEntity {
    var id: String
    var taskId: UUID
    var displayId: Int?
    var status: String
    var projectId: UUID
    var projectName: String

    static var defaultQuery: TaskCreationResultQuery { TaskCreationResultQuery() }

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Task Creation Result")
    }

    nonisolated var displayRepresentation: DisplayRepresentation {
        if let displayId {
            DisplayRepresentation(
                title: "T-\(displayId) created",
                subtitle: "Status: \(status) \u{2022} Project: \(projectName)"
            )
        } else {
            DisplayRepresentation(
                title: "Task created",
                subtitle: "Status: \(status) \u{2022} Project: \(projectName)"
            )
        }
    }

    @MainActor
    static func from(task: TransitTask, project: Project) -> TaskCreationResult {
        TaskCreationResult(
            id: task.id.uuidString,
            taskId: task.id,
            displayId: task.permanentDisplayId,
            status: task.statusRawValue,
            projectId: project.id,
            projectName: project.name
        )
    }
}

/// Minimal query for TaskCreationResult. Creation results are transient and
/// not independently queryable, so this returns empty results.
struct TaskCreationResultQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TaskCreationResult] {
        []
    }

    func suggestedEntities() async throws -> [TaskCreationResult] {
        []
    }
}
