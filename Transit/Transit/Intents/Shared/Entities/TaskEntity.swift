import AppIntents
import Foundation

struct TaskEntity: AppEntity {
    typealias DefaultQueryType = TaskEntityQuery

    var id: String
    var taskId: UUID
    var displayId: Int?
    var name: String
    var status: String
    var type: String
    var projectId: UUID
    var projectName: String
    var lastStatusChangeDate: Date
    var completionDate: Date?

    nonisolated static var defaultQuery: TaskEntityQuery {
        TaskEntityQuery()
    }

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Task")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(type.capitalized) • \(status.capitalized)"
        )
    }

    static func from(_ task: TransitTask) throws -> TaskEntity {
        guard let project = task.project else {
            throw VisualIntentError.invalidInput(
                "Task has no associated project (data integrity issue)"
            )
        }

        return TaskEntity(
            id: task.id.uuidString,
            taskId: task.id,
            displayId: task.permanentDisplayId,
            name: task.name,
            status: task.statusRawValue,
            type: task.typeRawValue,
            projectId: project.id,
            projectName: project.name,
            lastStatusChangeDate: task.lastStatusChangeDate,
            completionDate: task.completionDate
        )
    }
}
