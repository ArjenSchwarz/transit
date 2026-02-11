import AppIntents
import Foundation

/// Updates a task's status via JSON input. Exposed as "Transit: Update Status" in Shortcuts.
/// [req 17.1-17.6]
struct UpdateStatusIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Update Status"

    nonisolated(unsafe) static var description = IntentDescription(
        "Move a task to a different status. Use the task's display ID (e.g. 42 for T-42).",
        categoryName: "Tasks",
        resultValueName: "Status Change JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Input JSON",
        description: """
        JSON object with a task identifier and "status". Identify the task with either "displayId" \
        (integer, e.g. 42 for T-42) or "taskId" (UUID string). "status" must be one of: idea | planning | \
        spec | ready-for-implementation | in-progress | ready-for-review | done | abandoned. \
        Examples: {"displayId": 42, "status": "in-progress"} or {"taskId": "...", "status": "done"}
        """
    )
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

        guard let statusString = json["status"] as? String else {
            return IntentError.invalidInput(hint: "Missing required field: status").json
        }
        guard let newStatus = TaskStatus(rawValue: statusString) else {
            return IntentError.invalidStatus(hint: "Unknown status: \(statusString)").json
        }

        let task: TransitTask
        if let displayId = json["displayId"] as? Int {
            do {
                task = try taskService.findByDisplayID(displayId)
            } catch {
                return IntentError.taskNotFound(hint: "No task with displayId \(displayId)").json
            }
        } else if let taskIdString = json["taskId"] as? String, let taskId = UUID(uuidString: taskIdString) {
            do {
                task = try taskService.findByID(taskId)
            } catch {
                return IntentError.taskNotFound(hint: "No task with taskId \(taskIdString)").json
            }
        } else {
            return IntentError.invalidInput(hint: "Provide either displayId (integer) or taskId (UUID)").json
        }

        let previousStatus = task.statusRawValue
        do {
            try taskService.updateStatus(task: task, to: newStatus)
        } catch {
            return IntentError.invalidInput(hint: "Status update failed").json
        }

        var response: [String: Any] = [
            "taskId": task.id.uuidString,
            "previousStatus": previousStatus,
            "status": newStatus.rawValue
        ]
        if let displayId = task.permanentDisplayId {
            response["displayId"] = displayId
        }
        return IntentHelpers.encodeJSON(response)
    }
}
