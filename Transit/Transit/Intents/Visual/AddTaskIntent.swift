import AppIntents
import Foundation
import SwiftData

/// Creates a new task with visual parameter entry in Shortcuts.
/// Exposed as "Transit: Add Task" with native dropdowns for type and project.
struct AddTaskIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Add Task"

    nonisolated(unsafe) static var description = IntentDescription(
        "Create a new task in Transit with visual parameter entry",
        categoryName: "Tasks",
        resultValueName: "Task Creation Result"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(title: "Name")
    var name: String

    @Parameter(title: "Description")
    var taskDescription: String?

    @Parameter(title: "Type")
    var type: TaskType

    @Parameter(title: "Project")
    var project: ProjectEntity

    @Dependency
    private var taskService: TaskService

    @Dependency
    private var projectService: ProjectService

    /// Groups the user-supplied parameters for the testable execute method.
    struct Input {
        let name: String
        let taskDescription: String?
        let type: TaskType
        let project: ProjectEntity
    }

    @MainActor
    func perform() async throws -> some ReturnsValue<TaskCreationResult> {
        let input = Input(
            name: name,
            taskDescription: taskDescription,
            type: type,
            project: project
        )
        let result = try await AddTaskIntent.execute(
            input: input,
            taskService: taskService,
            projectService: projectService
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        input: Input,
        taskService: TaskService,
        projectService: ProjectService
    ) async throws -> TaskCreationResult {
        // Check that at least one project exists
        let descriptor = FetchDescriptor<Project>()
        let allProjects = (try? projectService.context.fetch(descriptor)) ?? []
        if allProjects.isEmpty {
            throw VisualIntentError.noProjects
        }

        // Validate non-empty name
        let trimmedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw VisualIntentError.invalidInput("Task name cannot be empty")
        }

        // Resolve project from entity
        let lookupResult = projectService.findProject(id: input.project.projectId)
        let resolvedProject: Project
        switch lookupResult {
        case .success(let found):
            resolvedProject = found
        case .failure:
            throw VisualIntentError.projectNotFound(input.project.name)
        }

        // Create task via TaskService
        let task: TransitTask
        do {
            task = try await taskService.createTask(
                name: trimmedName,
                description: input.taskDescription,
                type: input.type,
                project: resolvedProject
            )
        } catch {
            throw VisualIntentError.taskCreationFailed(error.localizedDescription)
        }

        return TaskCreationResult.from(task: task, project: resolvedProject)
    }
}
