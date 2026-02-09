import AppIntents
import Foundation

/// Updates a task's status via JSON input. Exposed as "Transit: Update Status" in Shortcuts.
/// [req 17.1-17.6]
struct UpdateStatusIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Update Status"
    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(title: "Input")
    var input: String

    @Dependency
    private var taskService: TaskService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = UpdateStatusIntent.execute(input: input, taskService: taskService)
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(input: String, taskService: TaskService) -> String {
        guard let json = IntentHelpers.parseJSON(input) else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        guard let displayId = json["displayId"] as? Int else {
            return IntentError.invalidInput(hint: "Missing required field: displayId").json
        }

        guard let statusString = json["status"] as? String else {
            return IntentError.invalidInput(hint: "Missing required field: status").json
        }
        guard let newStatus = TaskStatus(rawValue: statusString) else {
            return IntentError.invalidStatus(hint: "Unknown status: \(statusString)").json
        }

        guard let task = taskService.findByDisplayID(displayId) else {
            return IntentError.taskNotFound(hint: "No task with displayId \(displayId)").json
        }

        let previousStatus = task.statusRawValue
        taskService.updateStatus(task: task, to: newStatus)

        return IntentHelpers.encodeJSON([
            "displayId": displayId,
            "previousStatus": previousStatus,
            "status": newStatus.rawValue
        ])
    }
}
