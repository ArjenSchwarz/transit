import AppIntents
import Foundation
import SwiftData

/// Queries tasks with optional filters via JSON input. Exposed as "Transit: Query Tasks"
/// in Shortcuts. [req 18.1-18.5]
struct QueryTasksIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Query Tasks"

    nonisolated(unsafe) static var description = IntentDescription(
        "Search and filter tasks. Pass an empty string or {} to return all tasks.",
        categoryName: "Tasks",
        resultValueName: "Tasks JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Input JSON",
        description: """
        JSON object with optional filters: "status" (idea | planning | spec | ready-for-implementation | \
        in-progress | ready-for-review | done | abandoned), "type" (bug | feature | chore | research | \
        documentation), "projectId" (UUID). All filters are optional. \
        Example: {"status": "in-progress"} or {} for all tasks.
        """
    )
    var input: String

    @Dependency
    private var projectService: ProjectService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = QueryTasksIntent.execute(
            input: input,
            projectService: projectService,
            modelContext: projectService.context
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        input: String,
        projectService: ProjectService,
        modelContext: ModelContext
    ) -> String {
        let json = parseInput(input)
        guard let json else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        // Validate projectId filter if present
        if let error = validateProjectFilter(json, projectService: projectService) {
            return error.json
        }

        let allTasks = (try? modelContext.fetch(FetchDescriptor<TransitTask>())) ?? []
        let filtered = applyFilters(json, to: allTasks)
        return IntentHelpers.encodeJSONArray(filtered.map(taskToDict))
    }

    // MARK: - Private Helpers

    @MainActor private static func parseInput(_ input: String) -> [String: Any]? {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [:]
        }
        return IntentHelpers.parseJSON(input)
    }

    @MainActor private static func validateProjectFilter(
        _ json: [String: Any],
        projectService: ProjectService
    ) -> IntentError? {
        guard let idString = json["projectId"] as? String else { return nil }
        guard let projectId = UUID(uuidString: idString) else {
            return .invalidInput(hint: "Invalid projectId format")
        }
        if case .failure = projectService.findProject(id: projectId) {
            return .projectNotFound(hint: "No project with ID \(idString)")
        }
        return nil
    }

    @MainActor private static func applyFilters(
        _ json: [String: Any],
        to tasks: [TransitTask]
    ) -> [TransitTask] {
        var result = tasks
        if let status = json["status"] as? String {
            result = result.filter { $0.statusRawValue == status }
        }
        if let idString = json["projectId"] as? String,
           let projectId = UUID(uuidString: idString) {
            result = result.filter { $0.project?.id == projectId }
        }
        if let type = json["type"] as? String {
            result = result.filter { $0.typeRawValue == type }
        }
        return result
    }

    @MainActor private static func taskToDict(_ task: TransitTask) -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "taskId": task.id.uuidString,
            "name": task.name,
            "status": task.statusRawValue,
            "type": task.typeRawValue,
            "lastStatusChangeDate": isoFormatter.string(from: task.lastStatusChangeDate)
        ]
        if let displayId = task.permanentDisplayId {
            dict["displayId"] = displayId
        }
        if let projectId = task.project?.id.uuidString {
            dict["projectId"] = projectId
        }
        if let projectName = task.project?.name {
            dict["projectName"] = projectName
        }
        if let completionDate = task.completionDate {
            dict["completionDate"] = isoFormatter.string(from: completionDate)
        }
        return dict
    }
}
