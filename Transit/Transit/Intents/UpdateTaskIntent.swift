import AppIntents
import Foundation

/// Updates a task's mutable fields (name, description, type, metadata, milestone) via JSON input.
/// Exposed as "Transit: Update Task" in Shortcuts. [req 13.5]
///
/// Field validation, milestone resolution, and applier logic are delegated to
/// `TaskUpdateValidator` so this intent shares identical semantics with the MCP
/// `update_task` tool. The response shape is built by
/// `IntentHelpers.taskUpdateResponseDict` (AC 9.1).
struct UpdateTaskIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Update Task"

    nonisolated(unsafe) static var description = IntentDescription(
        "Update a task's mutable fields (name, description, type, metadata, milestone) in a single atomic call.",
        categoryName: "Tasks",
        resultValueName: "Task JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    /// Prose for the `input` @Parameter description. Exposed as a static so unit
    /// tests can assert on its content without reflecting over `@Parameter`
    /// metadata. The @Parameter macro requires a literal `LocalizedStringResource`
    /// at compile time, so the same text is duplicated in the @Parameter
    /// declaration below. Keep the two in sync. [Test seam: T-650 AC 8.2]
    nonisolated static let inputParameterDescription: String = """
    JSON object with a task identifier and optional update fields. \
    Identify task with "displayId" (integer) or "taskId" (UUID). \
    Update fields (omit any to preserve): \
    "name" (string, trimmed, non-empty); \
    "description" (string, trimmed; pass "" or whitespace-only to clear); \
    "type" (string, one of: bug, feature, chore, research, documentation); \
    "priority" (string, one of: low, medium, high; omit to leave unchanged — not clearable); \
    "metadata" (object with string values; replaces entire metadata dict; pass {} to clear all). \
    Milestone fields: "milestoneDisplayId" (integer), "milestone" (name within task's project), \
    or "clearMilestone" (boolean, true to remove). \
    Example: {"displayId": 42, "name": "Rename", "description": "new", "metadata": {"k": "v"}}
    """

    @Parameter(
        title: "Input JSON",
        description: """
        JSON object with a task identifier and optional update fields. \
        Identify task with "displayId" (integer) or "taskId" (UUID). \
        Update fields (omit any to preserve): \
        "name" (string, trimmed, non-empty); \
        "description" (string, trimmed; pass "" or whitespace-only to clear); \
        "type" (string, one of: bug, feature, chore, research, documentation); \
        "priority" (string, one of: low, medium, high; omit to leave unchanged — not clearable); \
        "metadata" (object with string values; replaces entire metadata dict; pass {} to clear all). \
        Milestone fields: "milestoneDisplayId" (integer), "milestone" (name within task's project), \
        or "clearMilestone" (boolean, true to remove). \
        Example: {"displayId": 42, "name": "Rename", "description": "new", "metadata": {"k": "v"}}
        """
    )
    var input: String

    @Dependency
    private var taskService: TaskService

    @Dependency
    private var milestoneService: MilestoneService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = UpdateTaskIntent.execute(
            input: input,
            taskService: taskService,
            milestoneService: milestoneService
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        input: String,
        taskService: TaskService,
        milestoneService: MilestoneService
    ) -> String {
        guard let json = IntentHelpers.parseJSON(input) else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        // Preflight identifier guard. "No task identifier provided" is structurally
        // different from "identifier provided but no match" — the former is
        // INVALID_INPUT, the latter is TASK_NOT_FOUND. Without this guard,
        // `taskService.resolveTask` would throw `.taskNotFound` for both. [T-650]
        let hasIdentifier = json["taskId"] != nil || json["displayId"] != nil
        guard hasIdentifier else {
            return IntentError.invalidInput(
                hint: "Provide either displayId (integer) or taskId (UUID string)"
            ).json
        }

        let task: TransitTask
        switch IntentHelpers.resolveTask(from: json, taskService: taskService) {
        case .success(let found): task = found
        case .failure(let error): return error.json
        }

        // Validate every field before applying any change. The validator is
        // pure — no mutations occur on success or failure, so an early return
        // here leaves the task untouched.
        let update: ValidatedTaskUpdate
        switch TaskUpdateValidator.validate(json, task: task, milestoneService: milestoneService) {
        case .success(let validated):
            update = validated
        case .failure(let error):
            return error.intentError.json
        }

        // No-op echo: when the request includes only an identifier (and no
        // mutating field), skip the save and return the current task JSON.
        guard update.hasChanges else {
            return IntentHelpers.encodeJSON(IntentHelpers.taskUpdateResponseDict(task))
        }

        // Apply in memory. If a service call throws between the two underlying
        // service calls (`updateTask` then `setMilestone`), explicitly roll
        // back so any partial mutation does not leak into the saved state.
        do {
            try TaskUpdateValidator.apply(
                update, to: task, taskService: taskService, milestoneService: milestoneService
            )
        } catch {
            taskService.rollback()
            return IntentError.internalError(
                hint: "Update failed: \(error.localizedDescription)"
            ).json
        }

        // Save. `TaskService.save()` already calls `safeRollback()` on failure.
        do {
            try taskService.save()
        } catch {
            return IntentError.internalError(
                hint: "Update failed: \(error.localizedDescription)"
            ).json
        }

        return IntentHelpers.encodeJSON(IntentHelpers.taskUpdateResponseDict(task))
    }
}
