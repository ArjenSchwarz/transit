import AppIntents
import Foundation

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

    @Parameter(
        title: "Input JSON",
        description: """
        JSON object with task details. Required fields: "name" (string), "type" (bug | feature | chore | \
        research | documentation). Optional: "projectId" (UUID), "project" (name), "description" (string), \
        "metadata" (object). Example: {"name": "Fix login", "type": "bug", "project": "Alpha"}
        """
    )
    var input: String

    @Dependency
    private var taskService: TaskService

    @Dependency
    private var projectService: ProjectService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = await CreateTaskIntent.execute(
            input: input,
            taskService: taskService,
            projectService: projectService
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        input: String,
        taskService: TaskService,
        projectService: ProjectService
    ) async -> String {
        guard let json = IntentHelpers.parseJSON(input) else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        if let error = validateInput(json) { return error.json }

        // Safe to force-unwrap: validateInput already verified these exist
        let name = json["name"] as! String // swiftlint:disable:this force_cast
        let typeRaw = json["type"] as! String // swiftlint:disable:this force_cast
        let taskType = TaskType(rawValue: typeRaw)! // swiftlint:disable:this force_unwrapping

        // Resolve project: projectId takes precedence over project name
        let projectId: UUID? = (json["projectId"] as? String).flatMap(UUID.init)
        let projectName = json["project"] as? String
        let lookupResult = projectService.findProject(id: projectId, name: projectName)

        let project: Project
        switch lookupResult {
        case .success(let found):
            project = found
        case .failure(let error):
            return IntentHelpers.mapProjectLookupError(error).json
        }

        let task: TransitTask
        do {
            task = try await taskService.createTask(
                name: name,
                description: json["description"] as? String,
                type: taskType,
                project: project,
                metadata: json["metadata"] as? [String: String]
            )
        } catch {
            return IntentError.invalidInput(hint: "Task creation failed").json
        }

        var response: [String: Any] = [
            "taskId": task.id.uuidString,
            "status": task.statusRawValue
        ]
        if let displayId = task.permanentDisplayId {
            response["displayId"] = displayId
        }
        return IntentHelpers.encodeJSON(response)
    }

    // MARK: - Private Helpers

    private static func validateInput(_ json: [String: Any]) -> IntentError? {
        guard let name = json["name"] as? String, !name.isEmpty else {
            return .invalidInput(hint: "Missing required field: name")
        }
        guard let typeString = json["type"] as? String else {
            return .invalidInput(hint: "Missing required field: type")
        }
        guard TaskType(rawValue: typeString) != nil else {
            return .invalidType(hint: "Unknown type: \(typeString)")
        }
        return nil
    }
}
