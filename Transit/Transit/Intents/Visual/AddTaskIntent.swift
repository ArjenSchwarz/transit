import AppIntents
import Foundation
import SwiftData

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

    @Parameter(
        title: "Metadata",
        description: "Optional key=value pairs, comma-separated (example: priority=high,source=shortcut)"
    )
    var metadata: String?

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
            metadata: metadata,
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
        metadata: String? = nil,
        services: Services
    ) async throws -> TaskCreationResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw VisualIntentError.invalidInput("Name is required.")
        }

        let parsedMetadata = try parseMetadata(metadata)

        guard hasAnyProjects(modelContext: services.projectService.context) else {
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
                project: resolvedProject,
                metadata: parsedMetadata
            )
        } catch TaskService.Error.invalidName {
            throw VisualIntentError.invalidInput("Name is required.")
        } catch {
            throw VisualIntentError.taskCreationFailed("Unable to create task.")
        }

        return try TaskCreationResult.from(task)
    }

    @MainActor
    private static func hasAnyProjects(modelContext: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Project>()
        descriptor.fetchLimit = 1
        let projects = (try? modelContext.fetch(descriptor)) ?? []
        return !projects.isEmpty
    }

    private static func parseMetadata(_ rawMetadata: String?) throws -> [String: String]? {
        guard let rawMetadata else {
            return nil
        }

        let trimmed = rawMetadata.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        var metadata: [String: String] = [:]
        let pairs = trimmed.split(separator: ",", omittingEmptySubsequences: false)
        for pair in pairs {
            let component = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !component.isEmpty else {
                throw VisualIntentError.invalidInput("Metadata contains an empty entry.")
            }

            let parts = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw VisualIntentError.invalidInput(
                    "Metadata must use key=value format separated by commas."
                )
            }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else {
                throw VisualIntentError.invalidInput(
                    "Metadata keys and values must be non-empty."
                )
            }

            metadata[key] = value
        }

        return metadata.isEmpty ? nil : metadata
    }
}
