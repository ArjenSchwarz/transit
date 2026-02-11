import AppIntents
import Foundation

struct TaskEntity: AppEntity {
    var id: String  // UUID string representation

    // Core properties (requirement 3.9)
    var taskId: UUID
    var displayId: Int?
    var name: String
    var status: String  // TaskStatus raw value
    var type: String    // TaskType raw value
    var projectId: UUID
    var projectName: String
    var lastStatusChangeDate: Date
    var completionDate: Date?

    // AppEntity requirements
    static var defaultQuery: TaskEntityQuery { TaskEntityQuery() }

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Task")
    }

    nonisolated var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(type.capitalized) • \(status.capitalized)"
        )
    }

    // Factory method from TransitTask model
    @MainActor
    static func from(_ task: TransitTask) throws -> TaskEntity {
        // Project is required in the data model; this should never be nil
        guard let project = task.project else {
            throw VisualIntentError.invalidInput("Task has no associated project (data integrity issue)")
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
