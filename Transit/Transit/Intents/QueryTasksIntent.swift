import Foundation
import SwiftData
#if canImport(AppIntents)
import AppIntents
#endif

#if canImport(AppIntents)
struct QueryTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Transit: Query Tasks"
    static let openAppWhenRun = false

    @Parameter(title: "Input JSON")
    var input: String

    @Dependency private var taskService: TaskService
    @Dependency private var projectService: ProjectService

    @MainActor
    func perform() async -> some IntentResult & ReturnsValue<String> {
        let output = Self.execute(
            input: input,
            taskService: taskService,
            projectService: projectService
        )
        return .result(value: output)
    }
}
#endif

extension QueryTasksIntent {
    struct Filters {
        let status: TaskStatus?
        let projectID: UUID?
    }

    @MainActor
    static func execute(
        input: String,
        taskService: TaskService,
        projectService: ProjectService
    ) -> String {
        let filters: Filters
        do {
            filters = try parseFilters(input: input, projectService: projectService)
        } catch let error as IntentError {
            return error.response
        } catch {
            return IntentError.invalidInput(hint: "Unable to parse query filters.").response
        }

        let tasks: [TransitTask]
        do {
            tasks = try fetchTasks(
                context: taskService.context,
                status: filters.status,
                projectID: filters.projectID
            )
        } catch {
            return IntentError.invalidInput(hint: "Unable to query tasks.").response
        }

        let response = makeResponse(tasks: tasks)
        return IntentJSON.encode(response)
    }

    @MainActor
    static func parseFilters(
        input: String,
        projectService: ProjectService
    ) throws -> Filters {
        guard let object = IntentJSON.parseObject(from: input) else {
            throw IntentError.invalidInput(
                hint: "Expected JSON object. Optional fields: status, projectId, project."
            )
        }

        let status = try parseStatusFilter(object["status"])
        let projectID = try parseProjectFilter(object: object, projectService: projectService)
        return Filters(status: status, projectID: projectID)
    }

    static func parseStatusFilter(_ rawStatus: Any?) throws -> TaskStatus? {
        guard let rawStatus else {
            return nil
        }
        guard let rawString = rawStatus as? String,
              let parsed = UpdateStatusIntent.parseStatus(rawString) else {
            throw IntentError.invalidStatus(hint: "Field 'status' must be a valid task status.")
        }
        return parsed
    }

    @MainActor
    static func parseProjectFilter(
        object: [String: Any],
        projectService: ProjectService
    ) throws -> UUID? {
        if let rawProjectID = object["projectId"] {
            guard let parsed = CreateTaskIntent.parseUUID(rawProjectID) else {
                throw IntentError.invalidInput(hint: "Field 'projectId' must be a UUID string.")
            }
            return parsed
        }
        guard let projectName = object["project"] as? String else {
            return nil
        }

        do {
            return try projectService.findProject(name: projectName).id
        } catch ProjectService.Error.projectNotFound {
            throw IntentError.projectNotFound(hint: "No matching project found for '\(projectName)'.")
        } catch ProjectService.Error.ambiguousProject {
            throw IntentError.ambiguousProject(hint: "Multiple projects matched by name. Provide projectId.")
        } catch {
            throw IntentError.invalidInput(hint: "Unable to resolve project filter.")
        }
    }

    @MainActor
    static func fetchTasks(
        context: ModelContext,
        status: TaskStatus?,
        projectID: UUID?
    ) throws -> [TransitTask] {
        let descriptor: FetchDescriptor<TransitTask>

        switch (status, projectID) {
        case let (.some(status), .some(projectID)):
            let rawStatus = status.rawValue
            descriptor = FetchDescriptor<TransitTask>(
                predicate: #Predicate<TransitTask> { task in
                    task.statusRawValue == rawStatus && task.project?.id == projectID
                },
                sortBy: [SortDescriptor(\TransitTask.lastStatusChangeDate, order: .reverse)]
            )
        case let (.some(status), .none):
            let rawStatus = status.rawValue
            descriptor = FetchDescriptor<TransitTask>(
                predicate: #Predicate<TransitTask> { task in
                    task.statusRawValue == rawStatus
                },
                sortBy: [SortDescriptor(\TransitTask.lastStatusChangeDate, order: .reverse)]
            )
        case let (.none, .some(projectID)):
            descriptor = FetchDescriptor<TransitTask>(
                predicate: #Predicate<TransitTask> { task in
                    task.project?.id == projectID
                },
                sortBy: [SortDescriptor(\TransitTask.lastStatusChangeDate, order: .reverse)]
            )
        case (.none, .none):
            descriptor = FetchDescriptor<TransitTask>(
                sortBy: [SortDescriptor(\TransitTask.lastStatusChangeDate, order: .reverse)]
            )
        }

        return try context.fetch(descriptor)
    }

    static func makeResponse(tasks: [TransitTask]) -> [String: Any] {
        var results = [[String: Any]]()
        results.reserveCapacity(tasks.count)

        for task in tasks {
            let entry: [String: Any] = [
                "taskId": task.id.uuidString.lowercased(),
                "displayId": task.permanentDisplayId as Any,
                "name": task.name,
                "status": task.status.rawValue,
                "type": task.type.rawValue,
                "projectId": task.project?.id.uuidString.lowercased() as Any
            ]
            results.append(entry)
        }

        return [
            "ok": true,
            "tasks": results
        ]
    }
}
