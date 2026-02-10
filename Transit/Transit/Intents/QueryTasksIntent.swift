import AppIntents
import Foundation
import SwiftData

/// App Intent for querying tasks via CLI/Shortcuts.
/// Accepts JSON with optional filters (status, projectId, type), returns task array.
struct QueryTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Transit: Query Tasks"
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

        // 3. Extract optional filters
        let statusFilter = json["status"] as? String
        let projectIdString = json["projectId"] as? String
        let typeFilter = json["type"] as? String

        // 4. Validate and resolve project if projectId provided
        var projectFilter: Project?
        if let projectIdString, let projectId = UUID(uuidString: projectIdString) {
            let projectResult = try services.projectService.findProjectForIntent(id: projectId, name: nil)
            guard case .success(let project) = projectResult else {
                if case .failure(let error) = projectResult {
                    return .result(value: error.json)
                }
                return .result(value: IntentError.projectNotFound(
                    hint: "No project with id \(projectIdString)"
                ).json)
            }
            projectFilter = project
        }

        // 5. Build predicate and fetch tasks
        let tasks = try await fetchTasks(
            taskService: services.taskService,
            statusFilter: statusFilter,
            projectFilter: projectFilter,
            typeFilter: typeFilter
        )

        // 6. Convert tasks to JSON array
        let taskArray = tasks.map { task -> [String: Any] in
            var dict: [String: Any] = [
                "taskId": task.id.uuidString,
                "displayId": task.permanentDisplayId ?? -1,
                "name": task.name,
                "status": task.status.rawValue,
                "type": task.type.rawValue,
                "projectId": task.project?.id.uuidString ?? "",
                "projectName": task.project?.name ?? "",
                "lastStatusChangeDate": ISO8601DateFormatter().string(from: task.lastStatusChangeDate)
            ]

            if let completionDate = task.completionDate {
                dict["completionDate"] = ISO8601DateFormatter().string(from: completionDate)
            }

            return dict
        }

        // 7. Encode response
        guard let responseData = try? JSONSerialization.data(withJSONObject: taskArray),
              let responseString = String(data: responseData, encoding: .utf8) else {
            return .result(value: IntentError.invalidInput(hint: "Failed to encode response").json)
        }

        return .result(value: responseString)
    }

    @MainActor
    private func fetchTasks(
        taskService: TaskService,
        statusFilter: String?,
        projectFilter: Project?,
        typeFilter: String?
    ) throws -> [TransitTask] {
        // Build predicate based on filters
        var predicates: [Predicate<TransitTask>] = []

        if let statusFilter, let status = TaskStatus(rawValue: statusFilter) {
            predicates.append(#Predicate { $0.statusRawValue == status.rawValue })
        }

        if let projectFilter {
            let projectId = projectFilter.id
            predicates.append(#Predicate { $0.project?.id == projectId })
        }

        if let typeFilter, let type = TaskType(rawValue: typeFilter) {
            predicates.append(#Predicate { $0.typeRawValue == type.rawValue })
        }

        // Combine predicates with AND logic
        let finalPredicate: Predicate<TransitTask>?
        if predicates.isEmpty {
            finalPredicate = nil
        } else if predicates.count == 1 {
            finalPredicate = predicates[0]
        } else {
            // Manually combine predicates
            finalPredicate = #Predicate<TransitTask> { task in
                predicates.allSatisfy { $0.evaluate(task) }
            }
        }

        return try taskService.queryTasks(predicate: finalPredicate)
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
