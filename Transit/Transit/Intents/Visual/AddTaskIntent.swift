import AppIntents
import Foundation

struct AddTaskIntent: AppIntent {
    struct Services {
        let taskService: TaskService
        let projectService: ProjectService
    }

    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Add Task"

    nonisolated(unsafe) static var description = IntentDescription(
        "Create a new task in Transit with visual parameter entry.",
        categoryName: "Tasks",
        resultValueName: "Task"
    )

    nonisolated(unsafe) static var supportedModes: IntentModes = [.foreground]

    @Parameter(title: "Name")
    var name: String

    @Parameter(title: "Description")
    var taskDescription: String?

    @Parameter(title: "Type")
    var type: TaskType

    @Parameter(title: "Project")
    var project: ProjectEntity

    // Metadata is intentionally not exposed here. See Decision 17 in
    // specs/shortcuts-friendly-intents/decision_log.md: comma-separated
    // key=value parsing is fragile for Shortcuts UI input. Metadata remains
    // available via the JSON-based CreateTaskIntent for power-user/CLI use.

    @Dependency
    private var taskService: TaskService

    @Dependency
    private var projectService: ProjectService

    @MainActor
    func perform() async throws -> some ReturnsValue<TaskCreationResult> {
        let result = try await Self.execute(
            name: name,
            taskDescription: taskDescription,
            type: type,
            project: project,
            services: Services(taskService: taskService, projectService: projectService)
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        name: String,
        taskDescription: String?,
        type: TaskType,
        project: ProjectEntity,
        services: Services
    ) async throws -> TaskCreationResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw VisualIntentError.invalidInput("Name is required.")
        }

        guard services.projectService.hasAnyProjects() else {
            throw VisualIntentError.noProjects
        }

        let resolvedProject: Project
        switch services.projectService.findProject(id: project.projectId) {
        case .success(let existingProject):
            resolvedProject = existingProject
        case .failure:
            throw VisualIntentError.projectNotFound(
                "Selected project no longer exists."
            )
        }

        let task: TransitTask
        do {
            task = try await services.taskService.createTask(
                name: trimmedName,
                description: taskDescription,
                type: type,
                project: resolvedProject
            )
        } catch TaskService.Error.invalidName {
            throw VisualIntentError.invalidInput("Name is required.")
        } catch {
            throw VisualIntentError.taskCreationFailed("Unable to create task.")
        }

        return try TaskCreationResult.from(task)
    }
}
