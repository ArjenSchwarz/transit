import AppIntents
import Foundation
import SwiftData

/// Visual Shortcuts intent for creating tasks with UI parameter entry.
/// Exposed as "Transit: Add Task" in Shortcuts. [req 2.1-2.13]
struct AddTaskIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Add Task"
    
    nonisolated(unsafe) static var description = IntentDescription(
        "Create a new task in Transit with visual parameter entry",
        categoryName: "Tasks",
        resultValueName: "Task Creation Result"
    )
    
    // Note: The design specifies `supportedModes: [.foreground]` for iOS 26,
    // but this API doesn't exist in the current SDK. Using `openAppWhenRun = true`
    // achieves the same behavior (opens app after task creation).
    nonisolated(unsafe) static var openAppWhenRun: Bool = true
    
    // MARK: - Parameters
    
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
    
    // MARK: - Perform
    
    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = try await AddTaskIntent.execute(
            name: name,
            taskDescription: taskDescription,
            type: type,
            project: project,
            taskService: taskService,
            projectService: projectService
        )
        
        // Encode result as JSON for Shortcuts compatibility
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try encoder.encode(result)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return .result(value: jsonString)
    }
    
    // MARK: - Logic (testable without @Dependency)
    
    @MainActor
    static func execute(
        name: String,
        taskDescription: String?,
        type: TaskType,
        project: ProjectEntity,
        taskService: TaskService,
        projectService: ProjectService
    ) async throws -> TaskCreationResult {
        // Check if any projects exist [req 2.6, 2.7]
        let descriptor = FetchDescriptor<Project>()
        let allProjects = try projectService.context.fetch(descriptor)
        guard !allProjects.isEmpty else {
            throw VisualIntentError.noProjects
        }
        
        // Validate non-empty task name [req 2.12]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw VisualIntentError.invalidInput("Task name cannot be empty")
        }
        
        // Resolve project from ProjectEntity [req 2.6, 2.7]
        let resolvedProject: Project
        do {
            let projectUUID = project.projectId
            resolvedProject = try projectService.context.fetch(
                FetchDescriptor<Project>(
                    predicate: #Predicate { $0.id == projectUUID }
                )
            ).first ?? {
                throw VisualIntentError.projectNotFound("Project '\(project.name)' no longer exists")
            }()
        } catch let error as VisualIntentError {
            throw error
        } catch {
            throw VisualIntentError.projectNotFound("Failed to find project: \(error.localizedDescription)")
        }
        
        // Create task via TaskService [req 2.13]
        // Tasks are always created in .idea status [req 2.8]
        let task: TransitTask
        do {
            task = try await taskService.createTask(
                name: trimmedName,
                description: taskDescription,
                type: type,
                project: resolvedProject,
                metadata: nil  // Metadata not supported in visual intent [design decision]
            )
        } catch TaskService.Error.invalidName {
            throw VisualIntentError.invalidInput("Task name is invalid")
        } catch {
            throw VisualIntentError.taskCreationFailed(error.localizedDescription)
        }
        
        // Return TaskCreationResult [req 2.10]
        return TaskCreationResult(
            taskId: task.id,
            displayId: task.permanentDisplayId,
            status: task.statusRawValue,
            projectId: resolvedProject.id,
            projectName: resolvedProject.name
        )
    }
}
