import AppIntents
import Foundation
import SwiftData

/// Creates a new task via JSON input. Exposed as "Transit: Create Task" in Shortcuts.
/// Always creates tasks in Idea status. [req 16.1-16.8]
struct CreateTaskIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Create Task"

    nonisolated(unsafe) static var description = IntentDescription(
        "Create a new task in Transit. The task starts in Idea status.",
        categoryName: "Tasks",
        resultValueName: "Task JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    /// Mirrors the `@Parameter(description:)` literal below; the App Intents macro
    /// requires a string literal, so this static MUST be updated in lock-step whenever
    /// the parameter description changes (T-1170).
    static let inputParameterDescription = """
        JSON object with task details. Required fields: "name" (string), "type" (bug | feature | chore | \
        research | documentation), and at least one of "projectId" (UUID) or "project" (name) to identify \
        the project. Optional: "description" (string), \
        "priority" (low | medium | high; defaults to medium), \
        "metadata" (object with string values; non-string values are ignored), "milestone" (name), \
        "milestoneDisplayId" (integer). \
        Example: {"name": "Fix login", "type": "bug", "project": "Alpha", "milestoneDisplayId": 1}
        """

    @Parameter(
        title: "Input JSON",
        description: """
        JSON object with task details. Required fields: "name" (string), "type" (bug | feature | chore | \
        research | documentation), and at least one of "projectId" (UUID) or "project" (name) to identify \
        the project. Optional: "description" (string), \
        "priority" (low | medium | high; defaults to medium), \
        "metadata" (object with string values; non-string values are ignored), "milestone" (name), \
        "milestoneDisplayId" (integer). \
        Example: {"name": "Fix login", "type": "bug", "project": "Alpha", "milestoneDisplayId": 1}
        """
    )
    var input: String

    @Dependency
    private var taskService: TaskService

    @Dependency
    private var projectService: ProjectService

    @Dependency
    private var milestoneService: MilestoneService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = await CreateTaskIntent.execute(
            input: input,
            taskService: taskService,
            projectService: projectService,
            milestoneService: milestoneService
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func execute(
        input: String,
        taskService: TaskService,
        projectService: ProjectService,
        milestoneService: MilestoneService? = nil,
        persistence: PersistenceAvailability = .shared
    ) async -> String {
        // Refuse to write while the in-memory fallback container is active [T-1836].
        if let unavailable = IntentHelpers.fallbackStorageErrorJSON(persistence) { return unavailable }

        guard let json = IntentHelpers.parseJSON(input) else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        if let error = validateInput(json) { return error.json }

        // Safe to force-unwrap: validateInput already verified these exist
        let name = json["name"] as! String // swiftlint:disable:this force_cast
        let typeRaw = json["type"] as! String // swiftlint:disable:this force_cast
        let taskType = TaskType(rawValue: typeRaw)! // swiftlint:disable:this force_unwrapping

        // Priority is optional and defaults to medium. Unlike the required `type`
        // force-unwrap above, this is an optional-with-default path: absent -> .medium;
        // present-and-invalid -> INVALID_PRIORITY (Decision 9); present-and-valid -> parse.
        let priority: TaskPriority
        switch parsePriority(json) {
        case .failure(let error): return error.json
        case .success(let parsed): priority = parsed
        }

        // Resolve project: projectId takes precedence over project name.
        // Validate key presence separately from string/UUID parsing so non-string
        // values (numbers, bools, etc.) are rejected too [T-743, T-788].
        let projectId: UUID?
        switch IntentHelpers.validateUUIDField("projectId", in: json) {
        case .failure(let error): return error.json
        case .success(let parsed): projectId = parsed
        }
        // Reject a present non-string `project` when projectId is absent [T-1453].
        // Without this guard `as? String` silently drops the malformed value and the
        // request falls through to the generic missing-project error instead of
        // surfacing the type mismatch. projectId-takes-precedence is preserved: when a
        // valid projectId is present the `project` name is ignored regardless of type.
        if projectId == nil, let rawProject = json["project"], !(rawProject is String) {
            return IntentError.invalidInput(hint: "project must be a string").json
        }
        let projectName = json["project"] as? String
        let lookupResult = projectService.findProject(id: projectId, name: projectName)

        let project: Project
        switch lookupResult {
        case .success(let found):
            project = found
        case .failure(let error):
            return IntentHelpers.mapProjectLookupError(error).json
        }

        // Resolve milestone before creating task to avoid orphaned tasks [T-260]
        let resolvedMilestone: Milestone?
        if let milestoneService {
            let (milestone, error) = resolveMilestone(from: json, in: project, using: milestoneService)
            if let error { return error }
            resolvedMilestone = milestone
        } else {
            resolvedMilestone = nil
        }

        let task: TransitTask
        do {
            task = try await taskService.createTask(
                name: name,
                description: json["description"] as? String,
                type: taskType,
                project: project,
                metadata: IntentHelpers.stringMetadata(from: json["metadata"]),
                priority: priority,
                milestone: resolvedMilestone
            )
        } catch {
            return mapCreateTaskError(error).json
        }

        return buildResponse(task)
    }

    // MARK: - Private Helpers

    /// Maps a `createTask` failure onto an intent error code. Milestone attachment and
    /// task creation now share one save, so this catch also covers what used to be a
    /// separate `setMilestone` failure. Keep input-shaped service errors on their
    /// specific codes and everything else (storage, allocator, cancellation) on
    /// INTERNAL_ERROR, so CLI callers can still tell a bad request from a retryable
    /// condition [T-1768].
    private static func mapCreateTaskError(_ error: Swift.Error) -> IntentError {
        switch error as? TaskService.Error {
        case .invalidName:
            .invalidInput(hint: "Task name cannot be empty")
        case .projectNotFound:
            .projectNotFound(hint: "The selected project could not be found")
        case .milestoneProjectMismatch:
            .milestoneProjectMismatch(hint: "Milestone and task must belong to the same project")
        case .milestoneNotOpen:
            .invalidInput(hint: "The selected milestone is no longer open")
        default:
            .internalError(hint: "Task creation failed")
        }
    }

    @MainActor
    private static func buildResponse(_ task: TransitTask) -> String {
        var response: [String: Any] = [
            "taskId": task.id.uuidString,
            "status": task.statusRawValue,
            // Effective-priority invariant (Req 1.4): echo the computed accessor.
            "priority": task.priority.rawValue
        ]
        if let displayId = task.permanentDisplayId {
            response["displayId"] = displayId
        }
        if let milestone = task.milestone {
            response["milestone"] = IntentHelpers.milestoneInfoDict(milestone)
        }
        return IntentHelpers.encodeJSON(response)
    }

    /// Resolves a milestone from JSON before task creation. Returns `(milestone, nil)` on success
    /// or `(nil, errorJSON)` on failure. Both nil means no milestone was requested.
    @MainActor
    private static func resolveMilestone(
        from json: [String: Any],
        in project: Project,
        using milestoneService: MilestoneService
    ) -> (milestone: Milestone?, error: String?) {
        // Parse via the shared helper so JSON booleans are rejected: JSONSerialization
        // delivers `true`/`false` as NSNumber(CFBoolean), which `as? Int` would otherwise
        // accept as 1/0 and silently target M-1/M-0 [T-1211, T-1283].
        let milestoneDisplayId = IntentHelpers.parseIntValue(json["milestoneDisplayId"])

        // Reject non-integer milestoneDisplayId when key is present [T-613]
        if json["milestoneDisplayId"] != nil, milestoneDisplayId == nil {
            return (nil, IntentError.invalidInput(hint: "milestoneDisplayId must be an integer").json)
        }

        // Reject non-string milestone only when milestoneDisplayId is absent. When both keys
        // are present, milestoneDisplayId takes priority and the `milestone` field is ignored,
        // matching the MCP handler and IntentHelpers.assignMilestone [T-1114].
        let milestoneName: String?
        if milestoneDisplayId == nil, json["milestone"] != nil {
            guard let name = json["milestone"] as? String else {
                return (nil, IntentError.invalidInput(hint: "milestone must be a string").json)
            }
            milestoneName = name
        } else {
            milestoneName = nil
        }

        if let milestoneDisplayId {
            return resolveMilestone(
                displayId: milestoneDisplayId, in: project, using: milestoneService
            )
        }
        if let milestoneName {
            return resolveMilestone(named: milestoneName, in: project, using: milestoneService)
        }
        return (nil, nil)
    }

    @MainActor
    private static func resolveMilestone(
        displayId: Int,
        in project: Project,
        using milestoneService: MilestoneService
    ) -> (milestone: Milestone?, error: String?) {
        do {
            let milestone = try milestoneService.findByDisplayID(displayId)
            guard milestone.project?.id == project.id else {
                return (nil, IntentHelpers.mapMilestoneError(.projectMismatch).json)
            }
            return (milestone, nil)
        } catch let error as MilestoneService.Error {
            return (nil, IntentHelpers.mapMilestoneError(error).json)
        } catch {
            return (nil, IntentError.internalError(
                hint: "Failed to look up milestone: \(error)"
            ).json)
        }
    }

    @MainActor
    private static func resolveMilestone(
        named name: String,
        in project: Project,
        using milestoneService: MilestoneService
    ) -> (milestone: Milestone?, error: String?) {
        do {
            guard let milestone = try milestoneService.findByName(name, in: project) else {
                return (nil, IntentError.milestoneNotFound(
                    hint: "No milestone named '\(name)' in project '\(project.name)'"
                ).json)
            }
            return (milestone, nil)
        } catch MilestoneService.Error.ambiguousName {
            return (nil, IntentError.ambiguousMilestone(
                hint: "Multiple milestones named '\(name)' exist in project '\(project.name)'"
            ).json)
        } catch {
            return (nil, IntentError.internalError(
                hint: "Failed to look up milestone: \(error)"
            ).json)
        }
    }

    /// Parses the optional `priority` field. Absent -> `.medium`;
    /// present-but-non-string -> INVALID_INPUT; present-but-unknown -> INVALID_PRIORITY
    /// (Decision 9). Priority is non-clearable, so there is no "absent = clear" case.
    private static func parsePriority(_ json: [String: Any]) -> Result<TaskPriority, IntentError> {
        guard let raw = json["priority"] else { return .success(.medium) }
        guard let str = raw as? String else {
            return .failure(.invalidInput(hint: "priority must be a string"))
        }
        guard let priority = TaskPriority(rawValue: str) else {
            return .failure(.invalidPriority(hint: "Unknown priority: \(str)"))
        }
        return .success(priority)
    }

    private static func validateInput(_ json: [String: Any]) -> IntentError? {
        guard json["name"] != nil else {
            return .invalidInput(hint: "Missing required field: name")
        }
        guard let name = json["name"] as? String else {
            return .invalidInput(hint: "name must be a string")
        }
        guard !name.isEmpty else {
            return .invalidInput(hint: "Missing required field: name")
        }
        guard json["type"] != nil else {
            return .invalidInput(hint: "Missing required field: type")
        }
        guard let typeString = json["type"] as? String else {
            return .invalidInput(hint: "type must be a string")
        }
        guard TaskType(rawValue: typeString) != nil else {
            return .invalidType(hint: "Unknown type: \(typeString)")
        }
        // Reject non-string description: as? String silently drops
        // present-but-wrong-type values, making a malformed request look successful. [T-1192]
        if let rawDescription = json["description"], rawDescription as? String == nil {
            return .invalidInput(hint: "description must be a string")
        }
        // A present metadata value must be an object. Keep the distinction from omission so
        // malformed values cannot be silently converted to nil by stringMetadata [T-1991].
        if let rawMetadata = json["metadata"], !IntentHelpers.isMetadataObject(rawMetadata) {
            return .invalidInput(hint: "metadata must be an object")
        }
        return nil
    }
}
