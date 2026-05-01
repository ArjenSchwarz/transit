#if os(macOS)
import Foundation
import SwiftData

// swiftlint:disable file_length

@MainActor
// swiftlint:disable:next type_body_length
final class MCPToolHandler {

    private let taskService: TaskService
    private let projectService: ProjectService
    private let commentService: CommentService
    private let milestoneService: MilestoneService
    private let maintenanceService: DisplayIDMaintenanceService
    private let settings: MCPSettings

    init(
        taskService: TaskService,
        projectService: ProjectService,
        commentService: CommentService,
        milestoneService: MilestoneService,
        maintenanceService: DisplayIDMaintenanceService,
        settings: MCPSettings
    ) {
        self.taskService = taskService
        self.projectService = projectService
        self.commentService = commentService
        self.milestoneService = milestoneService
        self.maintenanceService = maintenanceService
        self.settings = settings
    }

    // MARK: - JSON-RPC Dispatch

    /// Returns `nil` for JSON-RPC notifications (no response required).
    func handle(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        // Notifications have no id — the server must not reply.
        if request.id == nil {
            return nil
        }

        switch request.method {
        case "initialize":
            return handleInitialize(id: request.id)
        case "ping":
            return JSONRPCResponse.success(id: request.id, result: EmptyResult())
        case "tools/list":
            return handleToolsList(id: request.id)
        case "tools/call":
            return await handleToolCall(id: request.id, params: request.params)
        default:
            return JSONRPCResponse.error(
                id: request.id,
                code: JSONRPCErrorCode.methodNotFound,
                message: "Unknown method: \(request.method)"
            )
        }
    }

    // MARK: - Initialize

    private func handleInitialize(id: JSONRPCId?) -> JSONRPCResponse {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let result = MCPInitializeResult(
            protocolVersion: "2025-03-26",
            capabilities: MCPServerCapabilities(tools: MCPToolsCapability()),
            serverInfo: MCPServerInfo(name: "transit", version: version)
        )
        return JSONRPCResponse.success(id: id, result: result)
    }

    // MARK: - Tools List

    private func handleToolsList(id: JSONRPCId?) -> JSONRPCResponse {
        let tools = MCPToolsListResult(
            tools: MCPToolDefinitions.tools(includingMaintenance: settings.maintenanceToolsEnabled)
        )
        return JSONRPCResponse.success(id: id, result: tools)
    }

    // MARK: - Tools Call

    // swiftlint:disable:next cyclomatic_complexity
    private func handleToolCall(
        id: JSONRPCId?,
        params: AnyCodable?
    ) async -> JSONRPCResponse {
        guard let dict = params?.value as? [String: Any],
              let name = dict["name"] as? String else {
            return JSONRPCResponse.error(
                id: id,
                code: JSONRPCErrorCode.invalidParams,
                message: "Missing tool name"
            )
        }

        let arguments = dict["arguments"] as? [String: Any] ?? [:]

        // Gate maintenance tools behind the settings toggle. Distinct message so
        // callers can tell a disabled tool from an unknown one (AC 5.5).
        if MCPToolDefinitions.maintenanceToolNames.contains(name), !settings.maintenanceToolsEnabled {
            return JSONRPCResponse.error(
                id: id,
                code: JSONRPCErrorCode.methodNotFound,
                message: "Tool '\(name)' is disabled. Enable maintenance tools in Transit Settings."
            )
        }

        let result: MCPToolResult
        switch name {
        case "create_task":
            result = await handleCreateTask(arguments)
        case "update_task_status":
            result = handleUpdateStatus(arguments)
        case "query_tasks":
            result = handleQueryTasks(arguments)
        case "add_comment":
            result = handleAddComment(arguments)
        case "get_projects":
            result = handleGetProjects()
        case "create_milestone":
            result = await handleCreateMilestone(arguments)
        case "query_milestones":
            result = handleQueryMilestones(arguments)
        case "update_milestone":
            result = handleUpdateMilestone(arguments)
        case "delete_milestone":
            result = handleDeleteMilestone(arguments)
        case "update_task":
            result = handleUpdateTask(arguments)
        case "scan_duplicate_display_ids":
            result = handleScanDuplicateDisplayIds()
        case "reassign_duplicate_display_ids":
            result = await handleReassignDuplicateDisplayIds()
        default:
            return JSONRPCResponse.error(
                id: id,
                code: JSONRPCErrorCode.methodNotFound,
                message: "Unknown tool: \(name)"
            )
        }

        return JSONRPCResponse.success(id: id, result: result)
    }

    // MARK: - Maintenance Dispatch

    private func handleScanDuplicateDisplayIds() -> MCPToolResult {
        do {
            let report = try maintenanceService.scanDuplicates()
            return textResult(try IntentHelpers.encodeAsJSONString(report))
        } catch {
            return errorResult("Failed to scan duplicates: \(error.localizedDescription)")
        }
    }

    private func handleReassignDuplicateDisplayIds() async -> MCPToolResult {
        let result = await maintenanceService.reassignDuplicates()
        do {
            return textResult(try IntentHelpers.encodeAsJSONString(result))
        } catch {
            return errorResult("Failed to encode reassignment result: \(error.localizedDescription)")
        }
    }

    // MARK: - create_task

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func handleCreateTask(_ args: [String: Any]) async -> MCPToolResult {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return errorResult("Missing required argument: name")
        }
        guard let typeRaw = args["type"] as? String else {
            return errorResult("Missing required argument: type")
        }
        guard let taskType = TaskType(rawValue: typeRaw) else {
            let valid = TaskType.allCases.map(\.rawValue).joined(separator: ", ")
            return errorResult("Invalid type: \(typeRaw). Must be one of: \(valid)")
        }

        // Reject malformed projectId when the key is present [T-743]
        if let pidStr = args["projectId"] as? String, UUID(uuidString: pidStr) == nil {
            return errorResult("Invalid projectId: expected a UUID string")
        }
        let projectId = (args["projectId"] as? String).flatMap(UUID.init)
        let projectName = args["project"] as? String
        let project: Project
        switch projectService.findProject(id: projectId, name: projectName) {
        case .success(let found):
            project = found
        case .failure(let error):
            return errorResult(IntentHelpers.mapProjectLookupError(error).hint)
        }

        // Pre-validate milestone before creating the task to avoid orphans.
        // Reject non-integer milestoneDisplayId when key is present [T-613]
        if args["milestoneDisplayId"] != nil, IntentHelpers.parseIntValue(args["milestoneDisplayId"]) == nil {
            return errorResult("milestoneDisplayId must be an integer")
        }
        var resolvedMilestone: Milestone?
        if let milestoneDisplayId = IntentHelpers.parseIntValue(args["milestoneDisplayId"]) {
            do {
                resolvedMilestone = try milestoneService.findByDisplayID(milestoneDisplayId)
            } catch MilestoneService.Error.milestoneNotFound {
                return errorResult("No milestone with displayId \(milestoneDisplayId)")
            } catch MilestoneService.Error.duplicateDisplayID {
                return errorResult("Duplicate milestone identifier detected for displayId \(milestoneDisplayId)")
            } catch {
                return errorResult("Failed to find milestone: \(error)")
            }
            guard let milestoneProject = resolvedMilestone?.project,
                  milestoneProject.id == project.id else {
                return errorResult("Milestone and task must belong to the same project")
            }
        } else if let milestoneName = args["milestone"] as? String {
            guard let milestone = milestoneService.findByName(milestoneName, in: project) else {
                return errorResult("No milestone named '\(milestoneName)' in project '\(project.name)'")
            }
            resolvedMilestone = milestone
        }

        let task: TransitTask
        do {
            task = try await taskService.createTask(
                name: name,
                description: args["description"] as? String,
                type: taskType,
                project: project,
                metadata: IntentHelpers.stringMetadata(from: args["metadata"])
            )
        } catch {
            return errorResult("Task creation failed: \(error)")
        }

        if let milestone = resolvedMilestone {
            do {
                try milestoneService.setMilestone(milestone, on: task)
            } catch {
                // Pre-validation should prevent this, but clean up the task on unexpected failures.
                try? taskService.deleteTask(task)
                return errorResult("Failed to set milestone: \(error)")
            }
        }

        var response: [String: Any] = [
            "taskId": task.id.uuidString,
            "status": task.statusRawValue
        ]
        if let displayId = task.permanentDisplayId {
            response["displayId"] = displayId
        }
        if let milestone = task.milestone {
            var milestoneDict: [String: Any] = [
                "milestoneId": milestone.id.uuidString,
                "name": milestone.name
            ]
            if let mDisplayId = milestone.permanentDisplayId {
                milestoneDict["displayId"] = mDisplayId
            }
            response["milestone"] = milestoneDict
        }
        return textResult(IntentHelpers.encodeJSON(response))
    }

    // MARK: - update_task_status

    private func handleUpdateStatus(_ args: [String: Any]) -> MCPToolResult {
        guard let statusString = args["status"] as? String else {
            return errorResult("Missing required argument: status")
        }
        guard let newStatus = TaskStatus(rawValue: statusString) else {
            let valid = TaskStatus.allCases.map(\.rawValue).joined(separator: ", ")
            return errorResult("Invalid status: \(statusString). Must be one of: \(valid)")
        }

        // Reject non-integer displayId when key is present [T-634]
        if args["displayId"] != nil, IntentHelpers.parseIntValue(args["displayId"]) == nil {
            return errorResult("displayId must be an integer")
        }

        let task: TransitTask
        do {
            task = try taskService.resolveTask(from: args)
        } catch {
            return errorResult("Provide either displayId (integer) or taskId (UUID string)")
        }

        let commentText = args["comment"] as? String
        let commentAuthor = args["authorName"] as? String
        let (commentError, hasComment) = validateCommentArgs(comment: commentText, author: commentAuthor)
        if let commentError {
            return commentError
        }

        let previousStatus = task.statusRawValue
        do {
            try taskService.updateStatus(
                task: task, to: newStatus,
                comment: commentText, commentAuthor: commentAuthor, commentService: commentService
            )
        } catch {
            return errorResult("Status update failed: \(error)")
        }

        var response = statusResponse(task: task, previousStatus: previousStatus, newStatus: newStatus)
        appendCommentDetails(to: &response, taskID: task.id, hasComment: hasComment)
        return textResult(IntentHelpers.encodeJSON(response))
    }

    // MARK: - query_tasks

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func handleQueryTasks(_ args: [String: Any]) -> MCPToolResult {
        var projectFilter: UUID?
        if let pidStr = args["projectId"] as? String {
            guard let pid = UUID(uuidString: pidStr) else {
                return errorResult("Invalid projectId: expected a UUID string")
            }
            projectFilter = pid
        } else if let name = args["project"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch projectService.findProject(id: nil, name: name) {
            case .success(let found): projectFilter = found.id
            case .failure(let err): return errorResult(IntentHelpers.mapProjectLookupError(err).hint)
            }
        }

        // Resolve milestone filter
        // Reject non-integer milestoneDisplayId when key is present [T-613]
        if args["milestoneDisplayId"] != nil, IntentHelpers.parseIntValue(args["milestoneDisplayId"]) == nil {
            return errorResult("milestoneDisplayId must be an integer")
        }
        var milestoneFilter: Set<UUID>?
        if let milestoneDisplayId = IntentHelpers.parseIntValue(args["milestoneDisplayId"]) {
            do {
                milestoneFilter = [try milestoneService.findByDisplayID(milestoneDisplayId).id]
            } catch MilestoneService.Error.duplicateDisplayID {
                return errorResult("Duplicate milestone identifier detected for displayId \(milestoneDisplayId)")
            } catch {
                return textResult(IntentHelpers.encodeJSONArray([]))
            }
        } else if let milestoneName = args["milestone"] as? String,
                  !milestoneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let projectFilter {
                // Scoped to a single project — at most one milestone matches
                if case .success(let project) = projectService.findProject(id: projectFilter),
                   let milestone = milestoneService.findByName(milestoneName, in: project) {
                    milestoneFilter = [milestone.id]
                } else {
                    return textResult(IntentHelpers.encodeJSONArray([]))
                }
            } else {
                // No project filter — collect ALL milestones with this name across projects
                let allMilestones = (try? milestoneService.fetchAllMilestones()) ?? []
                let matchingIds = Set(
                    allMilestones
                        .filter { $0.name.localizedCaseInsensitiveCompare(milestoneName) == .orderedSame }
                        .map(\.id)
                )
                if matchingIds.isEmpty {
                    return textResult(IntentHelpers.encodeJSONArray([]))
                }
                milestoneFilter = matchingIds
            }
        }

        // Validate enum filters before building MCPQueryFilters [T-732]
        if let error = validateEnumFilter(args, key: "status", type: TaskStatus.self) { return error }
        if let error = validateEnumFilter(args, key: "not_status", type: TaskStatus.self) { return error }
        if let error = validateEnumFilter(args, key: "type", type: TaskType.self) { return error }

        let search = (args["search"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filters = MCPQueryFilters.from(
            args: args, type: args["type"] as? String, projectId: projectFilter,
            search: search?.isEmpty == true ? nil : search,
            milestoneIds: milestoneFilter
        )

        // Single-task lookup by displayId — returns early with detailed response
        // Reject non-integer displayId when key is present [T-634]
        if args["displayId"] != nil {
            guard let displayId = IntentHelpers.parseIntValue(args["displayId"]) else {
                return errorResult("displayId must be an integer")
            }
            return handleDisplayIdLookup(displayId, filters: filters)
        }

        // Full-table query
        let allTasks: [TransitTask]
        do {
            allTasks = try taskService.fetchAllTasks()
        } catch {
            return errorResult("Failed to fetch tasks: \(error)")
        }

        let filtered = allTasks.filter { filters.matches($0) }
        let isoFormatter = ISO8601DateFormatter()
        let results = filtered.map { taskToDict($0, formatter: isoFormatter) }
        return textResult(IntentHelpers.encodeJSONArray(results))
    }

    private func handleDisplayIdLookup(
        _ displayId: Int, filters: MCPQueryFilters
    ) -> MCPToolResult {
        let task: TransitTask
        do {
            task = try taskService.findByDisplayID(displayId)
        } catch TaskService.Error.taskNotFound {
            return textResult(IntentHelpers.encodeJSONArray([]))
        } catch {
            return errorResult("Lookup failed: \(error)")
        }

        guard filters.matches(task) else {
            return textResult(IntentHelpers.encodeJSONArray([]))
        }

        let isoFormatter = ISO8601DateFormatter()
        let dict = taskToDict(task, formatter: isoFormatter, detailed: true)
        return textResult(IntentHelpers.encodeJSONArray([dict]))
    }

}

// MARK: - create_milestone

extension MCPToolHandler {

    private func handleCreateMilestone(_ args: [String: Any]) async -> MCPToolResult {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return errorResult("Missing required argument: name")
        }

        // Reject malformed projectId when the key is present [T-743]
        if let pidStr = args["projectId"] as? String, UUID(uuidString: pidStr) == nil {
            return errorResult("Invalid projectId: expected a UUID string")
        }
        let projectId = (args["projectId"] as? String).flatMap(UUID.init)
        let projectName = args["project"] as? String
        let project: Project
        switch projectService.findProject(id: projectId, name: projectName) {
        case .success(let found):
            project = found
        case .failure(let error):
            return errorResult(IntentHelpers.mapProjectLookupError(error).hint)
        }

        let milestone: Milestone
        do {
            milestone = try await milestoneService.createMilestone(
                name: name,
                description: args["description"] as? String,
                project: project
            )
        } catch MilestoneService.Error.duplicateName {
            return errorResult("A milestone with this name already exists in the project")
        } catch MilestoneService.Error.invalidName {
            return errorResult("Milestone name cannot be empty")
        } catch {
            return errorResult("Milestone creation failed: \(error)")
        }

        let formatter = ISO8601DateFormatter()
        return textResult(IntentHelpers.encodeJSON(milestoneToDict(milestone, formatter: formatter)))
    }
}

// MARK: - query_milestones

extension MCPToolHandler {

    private func handleQueryMilestones(_ args: [String: Any]) -> MCPToolResult {
        // Single-milestone lookup by displayId
        // Reject non-integer displayId when key is present [T-634]
        if args["displayId"] != nil {
            guard let displayId = IntentHelpers.parseIntValue(args["displayId"]) else {
                return errorResult("displayId must be an integer")
            }
            return lookupMilestoneByDisplayId(displayId)
        }

        // Full query with filters
        let allMilestones: [Milestone]
        do {
            allMilestones = try milestoneService.fetchAllMilestones()
        } catch {
            return errorResult("Failed to fetch milestones: \(error)")
        }

        // Apply filters
        var filtered = allMilestones

        // Project filter
        switch resolveProjectFilter(args) {
        case .resolved(let pid):
            filtered = filtered.filter { $0.project?.id == pid }
        case .none:
            break
        case .error(let message):
            return errorResult(message)
        }

        // Status filter — validate enum values before filtering [T-732]
        if let error = validateEnumFilter(args, key: "status", type: MilestoneStatus.self) { return error }
        if let statusArray = args["status"] as? [String] {
            filtered = filtered.filter { statusArray.contains($0.statusRawValue) }
        } else if let statusSingle = args["status"] as? String {
            filtered = filtered.filter { $0.statusRawValue == statusSingle }
        }

        // Search filter
        if let search = args["search"] as? String,
           !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = filtered.filter {
                $0.name.localizedCaseInsensitiveContains(search)
                    || ($0.milestoneDescription?.localizedCaseInsensitiveContains(search) ?? false)
            }
        }

        let formatter = ISO8601DateFormatter()
        let results = filtered.map { milestoneToDict($0, formatter: formatter) }
        return textResult(IntentHelpers.encodeJSONArray(results))
    }

    private func lookupMilestoneByDisplayId(_ displayId: Int) -> MCPToolResult {
        do {
            let milestone = try milestoneService.findByDisplayID(displayId)
            let formatter = ISO8601DateFormatter()
            let dict = milestoneToDict(milestone, formatter: formatter, detailed: true)
            return textResult(IntentHelpers.encodeJSONArray([dict]))
        } catch MilestoneService.Error.duplicateDisplayID {
            return errorResult("Duplicate milestone identifier detected for displayId \(displayId)")
        } catch {
            return textResult(IntentHelpers.encodeJSONArray([]))
        }
    }

    private enum ProjectFilterResult {
        case resolved(UUID)
        case none
        case error(String)
    }

    private func resolveProjectFilter(_ args: [String: Any]) -> ProjectFilterResult {
        if let pidStr = args["projectId"] as? String {
            guard let pid = UUID(uuidString: pidStr) else {
                return .error("Invalid projectId: expected a UUID string")
            }
            return .resolved(pid)
        }
        if let name = args["project"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch projectService.findProject(id: nil, name: name) {
            case .success(let found):
                return .resolved(found.id)
            case .failure(let err):
                return .error(IntentHelpers.mapProjectLookupError(err).hint)
            }
        }
        return .none
    }
}

// MARK: - update_milestone

extension MCPToolHandler {

    private func handleUpdateMilestone(_ args: [String: Any]) -> MCPToolResult {
        let milestone: Milestone
        switch resolveMilestone(from: args) {
        case .success(let found): milestone = found
        case .failure(.message(let message)): return errorResult(message)
        }

        let previousStatus = milestone.statusRawValue

        // Validate all inputs before applying any changes (T-391: avoid partial updates)
        let validated: ValidatedMilestoneUpdate
        switch validateMilestoneUpdate(args, milestone: milestone) {
        case .valid(let update): validated = update
        case .invalid(let error): return error
        }

        // Apply all changes in memory, then save atomically
        applyMilestoneUpdate(validated, to: milestone)

        if validated.hasChanges {
            do {
                try milestoneService.save()
            } catch {
                return errorResult("Update failed: \(error)")
            }
        }

        let formatter = ISO8601DateFormatter()
        var response = milestoneToDict(milestone, formatter: formatter)
        response["previousStatus"] = previousStatus
        return textResult(IntentHelpers.encodeJSON(response))
    }

    private struct ValidatedMilestoneUpdate {
        let status: MilestoneStatus?
        let name: String?
        let description: String?
        var hasChanges: Bool { status != nil || name != nil || description != nil }
    }

    private enum MilestoneValidation {
        case valid(ValidatedMilestoneUpdate)
        case invalid(MCPToolResult)
    }

    private func validateMilestoneUpdate(
        _ args: [String: Any], milestone: Milestone
    ) -> MilestoneValidation {
        var newStatus: MilestoneStatus?
        if let statusRaw = args["status"] as? String {
            guard let parsed = MilestoneStatus(rawValue: statusRaw) else {
                let valid = MilestoneStatus.allCases.map(\.rawValue).joined(separator: ", ")
                return .invalid(errorResult("Invalid status: \(statusRaw). Must be one of: \(valid)"))
            }
            newStatus = parsed
        }

        var trimmedName: String?
        if let newName = args["name"] as? String {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .invalid(errorResult("Milestone name cannot be empty"))
            }
            if let project = milestone.project,
               milestoneService.milestoneNameExists(trimmed, in: project, excluding: milestone.id) {
                return .invalid(errorResult("A milestone with this name already exists in the project"))
            }
            trimmedName = trimmed
        }

        return .valid(ValidatedMilestoneUpdate(
            status: newStatus, name: trimmedName, description: args["description"] as? String
        ))
    }

    private func applyMilestoneUpdate(_ update: ValidatedMilestoneUpdate, to milestone: Milestone) {
        if let newStatus = update.status {
            milestone.statusRawValue = newStatus.rawValue
            milestone.lastStatusChangeDate = Date.now
            milestone.completionDate = newStatus.isTerminal ? Date.now : nil
        }
        if let name = update.name {
            milestone.name = name
        }
        if let description = update.description {
            milestone.milestoneDescription = description
        }
    }
}

// MARK: - delete_milestone

extension MCPToolHandler {

    private func handleDeleteMilestone(_ args: [String: Any]) -> MCPToolResult {
        let milestone: Milestone
        switch resolveMilestone(from: args) {
        case .success(let found): milestone = found
        case .failure(.message(let message)): return errorResult(message)
        }

        let milestoneId = milestone.id.uuidString
        let displayId = milestone.permanentDisplayId
        let name = milestone.name
        let affectedTasks = (milestone.tasks ?? []).count

        do {
            try milestoneService.deleteMilestone(milestone)
        } catch {
            return errorResult("Delete failed: \(error)")
        }

        var response: [String: Any] = [
            "deleted": true,
            "milestoneId": milestoneId,
            "name": name,
            "affectedTasks": affectedTasks
        ]
        if let displayId { response["displayId"] = displayId }
        return textResult(IntentHelpers.encodeJSON(response))
    }
}

// MARK: - update_task

extension MCPToolHandler {

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func handleUpdateTask(_ args: [String: Any]) -> MCPToolResult {
        // Reject non-integer displayId when key is present [T-634]
        if args["displayId"] != nil, IntentHelpers.parseIntValue(args["displayId"]) == nil {
            return errorResult("displayId must be an integer")
        }

        let task: TransitTask
        do {
            task = try taskService.resolveTask(from: args)
        } catch {
            return errorResult("Provide either displayId (integer) or taskId (UUID string)")
        }

        // Handle milestone assignment (save: false — deferred to single atomic save below)
        // Reject non-integer milestoneDisplayId when key is present [T-613]
        if args["milestoneDisplayId"] != nil, IntentHelpers.parseIntValue(args["milestoneDisplayId"]) == nil {
            return errorResult("milestoneDisplayId must be an integer")
        }
        // Reject non-boolean clearMilestone when key is present [T-1060]
        let clearMilestoneValue: Bool?
        if args.keys.contains("clearMilestone") {
            guard let parsed = IntentHelpers.parseBoolValue(args["clearMilestone"]) else {
                return errorResult("clearMilestone must be a boolean")
            }
            clearMilestoneValue = parsed
        } else {
            clearMilestoneValue = nil
        }
        if clearMilestoneValue == true {
            do {
                try milestoneService.setMilestone(nil, on: task, save: false)
            } catch {
                return errorResult("Failed to clear milestone: \(error)")
            }
        } else if let milestoneDisplayId = IntentHelpers.parseIntValue(args["milestoneDisplayId"]) {
            do {
                let milestone = try milestoneService.findByDisplayID(milestoneDisplayId)
                try milestoneService.setMilestone(milestone, on: task, save: false)
            } catch MilestoneService.Error.milestoneNotFound {
                return errorResult("No milestone with displayId \(milestoneDisplayId)")
            } catch MilestoneService.Error.duplicateDisplayID {
                return errorResult("Duplicate milestone identifier detected for displayId \(milestoneDisplayId)")
            } catch MilestoneService.Error.projectMismatch {
                return errorResult("Milestone and task must belong to the same project")
            } catch MilestoneService.Error.projectRequired {
                return errorResult("Task must belong to a project before assigning a milestone")
            } catch {
                return errorResult("Failed to set milestone: \(error)")
            }
        } else if let milestoneName = args["milestone"] as? String {
            guard let project = task.project else {
                return errorResult("Task must belong to a project before assigning a milestone")
            }
            guard let milestone = milestoneService.findByName(milestoneName, in: project) else {
                return errorResult("No milestone named '\(milestoneName)' in project '\(project.name)'")
            }
            do {
                try milestoneService.setMilestone(milestone, on: task, save: false)
            } catch {
                return errorResult("Failed to set milestone: \(error)")
            }
        }

        do {
            try taskService.save()
        } catch {
            return errorResult("Failed to save: \(error)")
        }

        let formatter = ISO8601DateFormatter()
        return textResult(IntentHelpers.encodeJSON(taskToDict(task, formatter: formatter)))
    }
}

// MARK: - get_projects, add_comment & Helpers

extension MCPToolHandler {

    private func handleGetProjects() -> MCPToolResult {
        let projects: [Project]
        do {
            projects = try projectService.fetchAllProjects(sortedByName: true)
        } catch {
            return errorResult("Failed to fetch projects: \(error)")
        }
        let results: [[String: Any]] = projects.map { project in
            var dict: [String: Any] = [
                "projectId": project.id.uuidString, "name": project.name,
                "description": project.projectDescription, "colorHex": project.colorHex,
                "activeTaskCount": projectService.activeTaskCount(for: project)
            ]
            if let gitRepo = project.gitRepo { dict["gitRepo"] = gitRepo }
            let milestones = milestoneService.milestonesForProject(project)
            if !milestones.isEmpty {
                dict["milestones"] = milestones.map { milestoneSummaryDict($0) }
            }
            return dict
        }
        return textResult(IntentHelpers.encodeJSONArray(results))
    }

    private func handleAddComment(_ args: [String: Any]) -> MCPToolResult {
        guard let content = args["content"] as? String, !content.isEmpty else {
            return errorResult("Missing required argument: content")
        }
        guard let authorName = args["authorName"] as? String, !authorName.isEmpty else {
            return errorResult("Missing required argument: authorName")
        }

        // Reject non-integer displayId when key is present [T-634]
        if args["displayId"] != nil, IntentHelpers.parseIntValue(args["displayId"]) == nil {
            return errorResult("displayId must be an integer")
        }

        let task: TransitTask
        do {
            task = try taskService.resolveTask(from: args)
        } catch {
            return errorResult("Provide either displayId (integer) or taskId (UUID string)")
        }

        let comment: Comment
        do {
            comment = try commentService.addComment(
                to: task, content: content, authorName: authorName, isAgent: true
            )
        } catch CommentService.Error.emptyContent {
            return errorResult("Comment content cannot be empty")
        } catch CommentService.Error.emptyAuthorName {
            return errorResult("Author name cannot be empty")
        } catch {
            return errorResult("Failed to add comment: \(error)")
        }

        let isoFormatter = ISO8601DateFormatter()
        let response: [String: Any] = [
            "id": comment.id.uuidString,
            "authorName": comment.authorName,
            "content": comment.content,
            "creationDate": isoFormatter.string(from: comment.creationDate)
        ]
        return textResult(IntentHelpers.encodeJSON(response))
    }

    // MARK: - Helpers

    private func validateCommentArgs(comment: String?, author: String?) -> (MCPToolResult?, Bool) {
        guard let comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (nil, false)
        }
        guard let author, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (errorResult("authorName is required when comment is provided"), false)
        }
        return (nil, true)
    }

    private func statusResponse(
        task: TransitTask, previousStatus: String, newStatus: TaskStatus
    ) -> [String: Any] {
        var res: [String: Any] = [
            "taskId": task.id.uuidString, "previousStatus": previousStatus, "status": newStatus.rawValue
        ]
        if let displayId = task.permanentDisplayId { res["displayId"] = displayId }
        return res
    }

    private func appendCommentDetails(to response: inout [String: Any], taskID: UUID, hasComment: Bool) {
        guard hasComment,
              let last = (try? commentService.fetchComments(for: taskID))?.last else { return }
        let fmt = ISO8601DateFormatter()
        response["comment"] = [
            "id": last.id.uuidString, "authorName": last.authorName,
            "content": last.content, "creationDate": fmt.string(from: last.creationDate)
        ] as [String: Any]
    }

    enum ResolveError: Error {
        case message(String)
    }

    private func textResult(_ text: String) -> MCPToolResult { MCPToolResult(content: [.text(text)], isError: nil) }
    private func errorResult(_ message: String) -> MCPToolResult {
        MCPToolResult(content: [.text(message)], isError: true)
    }

    /// Validate that all values for a given key are valid raw values of the specified enum.
    /// Returns an error result if any value is invalid, or nil if all are valid (or the key is absent).
    /// Works with both array and single-string inputs for backward compatibility.
    private func validateEnumFilter<E: RawRepresentable & CaseIterable>(
        _ args: [String: Any], key: String, type: E.Type
    ) -> MCPToolResult? where E.RawValue == String {
        let values: [String]
        if let array = args[key] as? [String] {
            values = array
        } else if let single = args[key] as? String {
            values = [single]
        } else {
            return nil
        }
        let allRaw = E.allCases.map(\.rawValue)
        let validRaw = Set(allRaw)
        let invalid = values.filter { !validRaw.contains($0) }
        guard invalid.isEmpty else {
            return errorResult(
                "Invalid \(key): \(invalid.joined(separator: ", ")). Must be one of: \(allRaw.joined(separator: ", "))"
            )
        }
        return nil
    }

    private func resolveMilestone(from args: [String: Any]) -> Result<Milestone, ResolveError> {
        // Reject non-integer displayId when key is present [T-634]
        if args["displayId"] != nil {
            guard let displayId = IntentHelpers.parseIntValue(args["displayId"]) else {
                return .failure(.message("displayId must be an integer"))
            }
            do {
                return .success(try milestoneService.findByDisplayID(displayId))
            } catch MilestoneService.Error.duplicateDisplayID {
                return .failure(.message("Duplicate milestone identifier detected for displayId \(displayId)"))
            } catch {
                return .failure(.message("No milestone with displayId \(displayId)"))
            }
        } else if let idStr = args["milestoneId"] as? String {
            // Validate UUID format separately from presence check [T-769]
            guard let milestoneId = UUID(uuidString: idStr) else {
                return .failure(.message("milestoneId must be a valid UUID string"))
            }
            do {
                return .success(try milestoneService.findByID(milestoneId))
            } catch {
                return .failure(.message("No milestone with milestoneId \(idStr)"))
            }
        } else {
            return .failure(.message("Provide either displayId (integer) or milestoneId (UUID string)"))
        }
    }

    private func milestoneToDict(
        _ milestone: Milestone, formatter: ISO8601DateFormatter, detailed: Bool = false
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "milestoneId": milestone.id.uuidString,
            "name": milestone.name,
            "status": milestone.statusRawValue,
            "creationDate": formatter.string(from: milestone.creationDate),
            "lastStatusChangeDate": formatter.string(from: milestone.lastStatusChangeDate)
        ]
        if let displayId = milestone.permanentDisplayId { dict["displayId"] = displayId }
        if let description = milestone.milestoneDescription { dict["description"] = description }
        if let projectId = milestone.project?.id.uuidString { dict["projectId"] = projectId }
        if let projectName = milestone.project?.name { dict["projectName"] = projectName }
        if let completionDate = milestone.completionDate {
            dict["completionDate"] = formatter.string(from: completionDate)
        }
        let tasks = milestone.tasks ?? []
        dict["taskCount"] = tasks.count
        if detailed {
            dict["tasks"] = tasks.map { task in
                var taskDict: [String: Any] = [
                    "name": task.name,
                    "status": task.statusRawValue,
                    "type": task.typeRawValue
                ]
                if let displayId = task.permanentDisplayId { taskDict["displayId"] = displayId }
                return taskDict
            }
        }
        return dict
    }

    private func milestoneSummaryDict(_ milestone: Milestone) -> [String: Any] {
        var dict: [String: Any] = [
            "milestoneId": milestone.id.uuidString,
            "name": milestone.name,
            "status": milestone.statusRawValue,
            "taskCount": (milestone.tasks ?? []).count
        ]
        if let displayId = milestone.permanentDisplayId { dict["displayId"] = displayId }
        return dict
    }

    private func taskToDict(
        _ task: TransitTask, formatter: ISO8601DateFormatter, detailed: Bool = false
    ) -> [String: Any] {
        var dict = IntentHelpers.taskToDict(task, formatter: formatter, detailed: detailed)
        let comments = (try? commentService.fetchComments(for: task.id)) ?? []
        dict["comments"] = comments.map { [
            "id": $0.id.uuidString, "authorName": $0.authorName, "content": $0.content,
            "isAgent": $0.isAgent, "creationDate": formatter.string(from: $0.creationDate)
        ] as [String: Any] }
        return dict
    }
}

#endif
