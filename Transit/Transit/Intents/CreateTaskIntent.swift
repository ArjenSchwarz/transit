import AppIntents
import Foundation
import SwiftData

/// App Intent for creating tasks via CLI/Shortcuts.
/// Accepts JSON input, resolves project, validates fields, creates task in Idea status.
struct CreateTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Transit: Create Task"
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

        // 3. Validate name
        guard let name = json["name"] as? String, !name.isEmpty else {
            return .result(value: IntentError.invalidInput(hint: "Missing required field: name").json)
        }

        // 4. Validate type
        guard let typeString = json["type"] as? String,
              let type = TaskType(rawValue: typeString) else {
            let provided = json["type"] as? String ?? "null"
            return .result(value: IntentError.invalidType(
                hint: "Invalid type '\(provided)'. Expected: feature, bug, chore, research, documentation"
            ).json)
        }

        // 5. Resolve project
        let projectId = (json["projectId"] as? String).flatMap(UUID.init)
        let projectName = json["project"] as? String
        let projectResult = try services.projectService.findProjectForIntent(id: projectId, name: projectName)

        guard case .success(let project) = projectResult else {
            if case .failure(let error) = projectResult {
                return .result(value: error.json)
            }
            return .result(value: IntentError.invalidInput(hint: "Project resolution failed").json)
        }

        // 6. Create task
        let task = try await services.taskService.createTask(
            name: name,
            description: json["description"] as? String,
            type: type,
            project: project,
            metadata: json["metadata"] as? [String: String]
        )

        // 7. Return response
        return .result(value: formatResponse(task))
    }

    private func parseJSON(_ input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func formatResponse(_ task: TransitTask) -> String {
        let displayId = task.permanentDisplayId ?? -1
        let response: [String: Any] = [
            "taskId": task.id.uuidString,
            "displayId": displayId,
            "status": "idea"
        ]

        guard let responseData = try? JSONSerialization.data(withJSONObject: response),
              let responseString = String(data: responseData, encoding: .utf8) else {
            return IntentError.invalidInput(hint: "Failed to encode response").json
        }

        return responseString
    }

    @MainActor
    private func getServices() async -> (taskService: TaskService, projectService: ProjectService)? {
        // Access services through a shared singleton
        // This is set up in TransitApp.init()
        return TransitServices.shared.services
    }
}

/// Shared services accessor for App Intents.
/// Populated by TransitApp on initialization.
@MainActor
final class TransitServices {
    static let shared = TransitServices()

    var services: (taskService: TaskService, projectService: ProjectService)?

    private init() {}
}
