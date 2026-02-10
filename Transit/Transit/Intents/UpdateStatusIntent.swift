import AppIntents
import Foundation
import SwiftData

/// App Intent for updating task status via CLI/Shortcuts.
/// Accepts JSON with displayId and status, validates and applies transition.
struct UpdateStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Transit: Update Status"
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Input")
    var input: String

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        // 1. Parse JSON input
        guard let json = parseJSON(input) else {
            return .result(value: IntentError.invalidInput(hint: "Expected valid JSON object").json)
        }

        // 2. Get services
        guard let services = await getServices() else {
            return .result(value: IntentError.invalidInput(hint: "Services not available").json)
        }

        // 3. Extract and validate displayId
        guard let taskJSON = json["task"] as? [String: Any],
              let displayId = taskJSON["displayId"] as? Int else {
            return .result(value: IntentError.invalidInput(
                hint: "Missing required field: task.displayId (integer)"
            ).json)
        }

        // 4. Find task by displayId
        guard let task = try services.taskService.findByDisplayID(displayId) else {
            return .result(value: IntentError.taskNotFound(
                hint: "No task with displayId \(displayId)"
            ).json)
        }

        // 5. Validate status
        guard let statusString = json["status"] as? String,
              let newStatus = TaskStatus(rawValue: statusString) else {
            let provided = json["status"] as? String ?? "null"
            let validStatuses = """
                idea, planning, spec, ready-for-implementation, in-progress, \
                ready-for-review, done, abandoned
                """
            return .result(value: IntentError.invalidStatus(
                hint: "Invalid status '\(provided)'. Expected: \(validStatuses)"
            ).json)
        }

        // 6. Apply status transition
        let previousStatus = task.status
        try services.taskService.updateStatus(task: task, to: newStatus)

        // 7. Return response
        let response: [String: Any] = [
            "displayId": displayId,
            "previousStatus": previousStatus.rawValue,
            "status": newStatus.rawValue
        ]

        guard let responseData = try? JSONSerialization.data(withJSONObject: response),
              let responseString = String(data: responseData, encoding: .utf8) else {
            return .result(value: IntentError.invalidInput(hint: "Failed to encode response").json)
        }

        return .result(value: responseString)
    }

    private func parseJSON(_ input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    @MainActor
    private func getServices() async -> (taskService: TaskService, projectService: ProjectService)? {
        return TransitServices.shared.services
    }
}
