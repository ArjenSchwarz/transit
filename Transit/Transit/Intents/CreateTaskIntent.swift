import Foundation
#if canImport(AppIntents)
import AppIntents
#endif

#if canImport(AppIntents)
struct CreateTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Transit: Create Task"
    static let openAppWhenRun = false

    @Parameter(title: "Input JSON")
    var input: String

    @Dependency private var taskService: TaskService
    @Dependency private var projectService: ProjectService

    @MainActor
    func perform() async -> some IntentResult & ReturnsValue<String> {
        let output = await Self.execute(
            input: input,
            taskService: taskService,
            projectService: projectService
        )
        return .result(value: output)
    }
}
#endif

extension CreateTaskIntent {
    struct Request {
        let name: String
        let type: TaskType
        let projectID: UUID?
        let projectName: String?
        let description: String?
        let metadata: [String: String]?
    }

    @MainActor
    static func execute(
        input: String,
        taskService: TaskService,
        projectService: ProjectService
    ) async -> String {
        let request: Request
        do {
            request = try parseRequest(input)
        } catch let error as IntentError {
            return error.response
        } catch {
            return IntentError.invalidInput(hint: "Invalid request payload.").response
        }

        let project: Project
        do {
            project = try resolveProject(request: request, projectService: projectService)
        } catch let error as IntentError {
            return error.response
        } catch {
            return IntentError.invalidInput(hint: "Unable to resolve project.").response
        }

        do {
            return try await createTaskResponse(request: request, project: project, taskService: taskService)
        } catch let error as IntentError {
            return error.response
        } catch {
            return IntentError.invalidInput(hint: "Unable to create task.").response
        }
    }

    static func parseRequest(_ input: String) throws -> Request {
        guard let object = IntentJSON.parseObject(from: input) else {
            throw IntentError.invalidInput(
                hint: "Expected JSON object with projectId/project, name, type, optional description and metadata."
            )
        }

        guard let name = object["name"] as? String else {
            throw IntentError.invalidInput(hint: "Field 'name' is required.")
        }
        guard let typeValue = object["type"] as? String,
              let type = parseType(typeValue) else {
            throw IntentError.invalidType(
                hint: "Field 'type' must be one of: bug, feature, chore, research, documentation."
            )
        }

        let projectID = parseUUID(object["projectId"])
        let projectName = projectID == nil ? (object["project"] as? String) : nil
        let description = object["description"] as? String
        let metadata = try parseMetadataField(object["metadata"])

        return Request(
            name: name,
            type: type,
            projectID: projectID,
            projectName: projectName,
            description: description,
            metadata: metadata
        )
    }

    static func parseMetadataField(_ rawValue: Any?) throws -> [String: String]? {
        guard let rawValue else {
            return nil
        }
        guard let metadata = parseMetadata(rawValue) else {
            throw IntentError.invalidInput(hint: "Field 'metadata' must be an object containing string values.")
        }
        return metadata
    }

    @MainActor
    static func resolveProject(request: Request, projectService: ProjectService) throws -> Project {
        do {
            return try projectService.findProject(id: request.projectID, name: request.projectName)
        } catch let error as ProjectService.Error {
            switch error {
            case .projectNotFound:
                throw IntentError.projectNotFound(
                    hint: "No matching project found. Provide a valid projectId or project name."
                )
            case .ambiguousProject:
                throw IntentError.ambiguousProject(hint: "Multiple projects matched by name. Provide projectId.")
            case .missingLookup:
                throw IntentError.invalidInput(hint: "Provide either 'projectId' or 'project'.")
            case .invalidDescription, .invalidName:
                throw IntentError.invalidInput(hint: "Invalid project data.")
            }
        }
    }

    @MainActor
    static func createTaskResponse(
        request: Request,
        project: Project,
        taskService: TaskService
    ) async throws -> String {
        do {
            let task = try await taskService.createTask(
                project: project,
                name: request.name,
                description: request.description,
                type: request.type,
                metadata: request.metadata
            )
            let payload: [String: Any] = [
                "ok": true,
                "taskId": task.id.uuidString.lowercased(),
                "displayId": task.permanentDisplayId as Any,
                "status": task.status.rawValue
            ]
            return IntentJSON.encode(payload)
        } catch let error as TaskService.Error {
            switch error {
            case .invalidName:
                throw IntentError.invalidInput(hint: "Field 'name' must not be empty.")
            case .missingProject:
                throw IntentError.projectNotFound(hint: "Project is required.")
            case .taskNotFound, .duplicateDisplayID, .restoreRequiresAbandonedTask:
                throw IntentError.invalidInput(hint: "Unable to create task.")
            }
        }
    }

    static func parseType(_ value: String) -> TaskType? {
        TaskType(
            rawValue: value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        )
    }

    static func parseMetadata(_ rawValue: Any) -> [String: String]? {
        guard let dictionary = rawValue as? [String: Any] else {
            return nil
        }

        var metadata = [String: String](minimumCapacity: dictionary.count)
        for (key, value) in dictionary {
            guard let stringValue = value as? String else {
                return nil
            }
            metadata[key] = stringValue
        }
        return metadata
    }

    static func parseUUID(_ rawValue: Any?) -> UUID? {
        guard let rawValue else {
            return nil
        }
        if let string = rawValue as? String {
            return UUID(uuidString: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

}
