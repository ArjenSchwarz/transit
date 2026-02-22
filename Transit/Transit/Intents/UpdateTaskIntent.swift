import AppIntents
import Foundation

/// Updates a task's properties (currently milestone assignment) via JSON input.
/// Exposed as "Transit: Update Task" in Shortcuts. [req 13.5]
struct UpdateTaskIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Update Task"

    nonisolated(unsafe) static var description = IntentDescription(
        "Update a task's properties. Currently supports milestone assignment.",
        categoryName: "Tasks",
        resultValueName: "Task JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Input JSON",
        description: """
        JSON object with a task identifier and update fields. Identify task with "displayId" (integer) \
        or "taskId" (UUID). Milestone assignment: "milestoneDisplayId" (integer), "milestone" (name within \
        task's project), or "clearMilestone" (boolean, true to remove). \
        Example: {"displayId": 42, "milestoneDisplayId": 1}
        """
    )
    var input: String

    @Dependency
    private var taskService: TaskService

    @Dependency
    private var milestoneService: MilestoneService

    @Dependency
    private var projectService: ProjectService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = UpdateTaskIntent.execute(
            input: input,
            taskService: taskService,
            milestoneService: milestoneService,
            projectService: projectService
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        input: String,
        taskService: TaskService,
        milestoneService: MilestoneService,
        projectService: ProjectService
    ) -> String {
        guard let json = IntentHelpers.parseJSON(input) else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        let task: TransitTask
        switch IntentHelpers.resolveTask(from: json, taskService: taskService) {
        case .success(let found): task = found
        case .failure(let error): return error.json
        }

        if let error = applyMilestoneChange(json, task: task, milestoneService: milestoneService) {
            return error
        }

        return buildResponse(task)
    }

    // MARK: - Private Helpers

    @MainActor
    private static func applyMilestoneChange(
        _ json: [String: Any],
        task: TransitTask,
        milestoneService: MilestoneService
    ) -> String? {
        if let clearMilestone = json["clearMilestone"] as? Bool, clearMilestone {
            do {
                try milestoneService.setMilestone(nil, on: task)
            } catch let error as MilestoneService.Error {
                return IntentHelpers.mapMilestoneError(error).json
            } catch {
                return IntentError.invalidInput(hint: "Failed to clear milestone").json
            }
            return nil
        }
        return IntentHelpers.assignMilestone(from: json, to: task, milestoneService: milestoneService)
    }

    @MainActor
    private static func buildResponse(_ task: TransitTask) -> String {
        var response: [String: Any] = [
            "taskId": task.id.uuidString,
            "name": task.name,
            "status": task.statusRawValue,
            "type": task.typeRawValue
        ]
        if let displayId = task.permanentDisplayId {
            response["displayId"] = displayId
        }
        if let project = task.project {
            response["projectId"] = project.id.uuidString
            response["projectName"] = project.name
        }
        if let milestone = task.milestone {
            response["milestone"] = IntentHelpers.milestoneInfoDict(milestone)
        }
        return IntentHelpers.encodeJSON(response)
    }
}
