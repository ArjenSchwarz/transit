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
        // JSON-RPC 2.0 §4.2/§5: reject non-"2.0" with -32600, even on notification-shaped envelopes (T-1106).
        guard request.jsonrpc == "2.0" else {
            return JSONRPCResponse.error(
                id: request.id,
                code: JSONRPCErrorCode.invalidRequest,
                message: "Invalid Request: jsonrpc must be \"2.0\""
            )
        }

        // Notifications omit the `id` member entirely (per JSON-RPC 2.0 §4.1).
        // An explicit `"id": null` is a regular request and must receive a
        // response with `id: null`, so we rely on the parsed notification
        // flag rather than `request.id == nil`.
        if request.isNotification {
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

    // swiftlint:disable:next cyclomatic_complexity function_body_length
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

        let arguments: [String: Any]
        switch parseArgumentsEnvelope(dict) {
        case .success(let parsed):
            arguments = parsed
        case .failure(.message(let message)):
            return JSONRPCResponse.error(id: id, code: JSONRPCErrorCode.invalidParams, message: message)
        }

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

        // Priority is optional and defaults to medium. A present-but-invalid value
        // is rejected before any task is created (Req 5.5).
        let priority: TaskPriority
        if let priorityRaw = args["priority"] {
            guard let priorityStr = priorityRaw as? String else {
                return errorResult("priority must be a string")
            }
            guard let parsed = TaskPriority(rawValue: priorityStr) else {
                let valid = TaskPriority.allCases.map(\.rawValue).joined(separator: ", ")
                return errorResult("Invalid priority: \(priorityStr). Must be one of: \(valid)")
            }
            priority = parsed
        } else {
            priority = .medium
        }

        // Reject malformed or non-string projectId when the key is present
        // [T-743, T-788].
        let projectId: UUID?
        switch parseProjectIdArgument(args) {
        case .failure(.message(let message)): return errorResult(message)
        case .success(let parsed): projectId = parsed
        }
        // Reject a present non-string `project` when projectId is absent [T-1453].
        // Without this guard `as? String` silently drops the malformed value and the
        // request falls through to the generic missing-project error instead of
        // surfacing the type mismatch. projectId-takes-precedence is preserved: when a
        // valid projectId is present the `project` name is ignored regardless of type.
        if projectId == nil, let rawProject = args["project"], !(rawProject is String) {
            return errorResult("project must be a string")
        }
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
        } else if args["milestone"] != nil {
            // Reject non-string milestone values [T-1114]. Without this guard
            // a numeric or boolean milestone arg would fall through to the
            // "absent" branch and the task would be created without the
            // requested assignment.
            guard let milestoneName = args["milestone"] as? String else {
                return errorResult("milestone must be a string")
            }
            guard let milestone = milestoneService.findByName(milestoneName, in: project) else {
                return errorResult("No milestone named '\(milestoneName)' in project '\(project.name)'")
            }
            resolvedMilestone = milestone
        }

        // Reject non-string description: as? String silently drops
        // present-but-wrong-type values, making a malformed request look successful. [T-1192]
        if args["description"] != nil, args["description"] as? String == nil {
            return errorResult("description must be a string")
        }

        let task: TransitTask
        do {
            task = try await taskService.createTask(
                name: name,
                description: args["description"] as? String,
                type: taskType,
                project: project,
                metadata: IntentHelpers.stringMetadata(from: args["metadata"]),
                priority: priority
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
            "status": task.statusRawValue,
            "priority": task.priority.rawValue
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
        // When the "status" argument is present it MUST be a string — a non-string
        // value would otherwise be silently dropped by `as? String` and misreported
        // as missing. Reject it before any mutation, like the milestone paths [T-1544].
        guard args["status"] != nil else {
            return errorResult("Missing required argument: status")
        }
        guard let statusString = args["status"] as? String else {
            return errorResult("status must be a string")
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
        } catch TaskService.Error.invalidIdentifier(let field) {
            // Reject malformed identifiers with a field-specific message
            // instead of returning the generic not-found error. [T-808]
            return errorResult(IntentHelpers.invalidIdentifierHint(for: field))
        } catch {
            return errorResult("Provide either displayId (integer) or taskId (UUID string)")
        }

        // Reject non-string comment/authorName: as? String silently drops
        // present-but-wrong-type values, dropping the audit-trail entry. [T-1205]
        if args["comment"] != nil, !(args["comment"] is String) {
            return errorResult("comment must be a string")
        }
        if args["authorName"] != nil, !(args["authorName"] is String) {
            return errorResult("authorName must be a string")
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
        // Reject malformed or non-string projectId when the key is present
        // [T-665, T-788].
        let parsedProjectId: UUID?
        switch parseProjectIdArgument(args) {
        case .failure(.message(let message)): return errorResult(message)
        case .success(let parsed): parsedProjectId = parsed
        }
        // Reject non-string `project` filter [T-1116].
        if args["project"] != nil, !(args["project"] is String) {
            return errorResult("project must be a string")
        }
        var projectFilter: UUID?
        if let pid = parsedProjectId {
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
        // Reject non-string `milestone` name filter [T-1266]. Without this guard a
        // numeric/boolean/array milestone falls through the `as? String` cast below
        // to the "no milestone filter" branch, returning every task unfiltered.
        if args["milestone"] != nil, !(args["milestone"] is String) {
            return errorResult("milestone must be a string")
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
        // type is a single-value filter (schema declares a string enum; read back as
        // args["type"] as? String). Reject arrays so they aren't silently dropped. [T-1404]
        if let error = validateEnumFilter(args, key: "type", type: TaskType.self, allowArray: false) {
            return error
        }
        // priority is a multi-value filter (schema declares an array, mirroring status).
        if let error = validateEnumFilter(args, key: "priority", type: TaskPriority.self, allowArray: true) {
            return error
        }

        // Reject a present-but-non-boolean `unfinished` flag [T-1095]. A plain
        // `as? Bool` would silently coerce "true"/1/null to false, returning
        // done/abandoned tasks even though the caller requested unfinished-only.
        if let unfinishedArg = args["unfinished"], IntentHelpers.parseBoolValue(unfinishedArg) == nil {
            return errorResult("unfinished must be a boolean")
        }

        // Reject non-string `search` filter [T-1156]. A present non-string value must not be
        // silently dropped by `as? String`, which would broaden results instead of erroring.
        if args["search"] != nil, !(args["search"] is String) {
            return errorResult("search must be a string")
        }

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

        // Reject malformed or non-string projectId when the key is present
        // [T-743, T-788].
        let projectId: UUID?
        switch parseProjectIdArgument(args) {
        case .failure(.message(let message)): return errorResult(message)
        case .success(let parsed): projectId = parsed
        }
        // Reject a present non-string `project` when projectId is absent [T-1453].
        // Mirrors handleCreateTask: a malformed `project` must surface as a type
        // mismatch rather than being silently dropped by `as? String`.
        if projectId == nil, let rawProject = args["project"], !(rawProject is String) {
            return errorResult("project must be a string")
        }
        let projectName = args["project"] as? String
        let project: Project
        switch projectService.findProject(id: projectId, name: projectName) {
        case .success(let found):
            project = found
        case .failure(let error):
            return errorResult(IntentHelpers.mapProjectLookupError(error).hint)
        }

        // Reject non-string description: as? String silently drops
        // present-but-wrong-type values, making a malformed request look successful. [T-1192]
        if args["description"] != nil, args["description"] as? String == nil {
            return errorResult("description must be a string")
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
        // Validate filter inputs first so a displayId lookup can't bypass validation [T-963].
        // Resolve the project filter once and reuse it for both the displayId match and the
        // full-table filter pass.
        let projectFilter: UUID?
        switch resolveProjectFilter(args) {
        case .resolved(let pid): projectFilter = pid
        case .none: projectFilter = nil
        case .error(let message): return errorResult(message)
        }

        // Status filter — validate enum values before filtering [T-732]
        if let error = validateEnumFilter(args, key: "status", type: MilestoneStatus.self) { return error }

        // Reject non-string `search` filter [T-1156]. Validated before the displayId branch so a
        // malformed value can't bypass validation by silently dropping through `as? String`.
        if args["search"] != nil, !(args["search"] is String) {
            return errorResult("search must be a string")
        }

        // Single-milestone lookup by displayId. Remaining filters still apply conjunctively —
        // a milestone that does not satisfy them is filtered out, mirroring handleQueryTasks [T-963].
        if args["displayId"] != nil {
            guard let displayId = IntentHelpers.parseIntValue(args["displayId"]) else {
                return errorResult("displayId must be an integer")
            }
            return lookupMilestoneByDisplayId(displayId, args: args, projectFilter: projectFilter)
        }

        // Full query with filters
        let allMilestones: [Milestone]
        do {
            allMilestones = try milestoneService.fetchAllMilestones()
        } catch {
            return errorResult("Failed to fetch milestones: \(error)")
        }

        let filtered = allMilestones.filter { milestoneMatches($0, args: args, projectFilter: projectFilter) }
        let formatter = ISO8601DateFormatter()
        let results = filtered.map { milestoneToDict($0, formatter: formatter) }
        return textResult(IntentHelpers.encodeJSONArray(results))
    }

    /// Returns true when `milestone` satisfies the project/status/search filters in `args`.
    /// Callers must pre-validate filter inputs.
    private func milestoneMatches(
        _ milestone: Milestone, args: [String: Any], projectFilter: UUID?
    ) -> Bool {
        if let projectFilter, milestone.project?.id != projectFilter {
            return false
        }
        if let statusArray = args["status"] as? [String] {
            if !statusArray.contains(milestone.statusRawValue) { return false }
        } else if let statusSingle = args["status"] as? String {
            if milestone.statusRawValue != statusSingle { return false }
        }
        if let search = args["search"] as? String,
           !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let nameMatch = milestone.name.localizedCaseInsensitiveContains(search)
            let descMatch = milestone.milestoneDescription?.localizedCaseInsensitiveContains(search) ?? false
            if !nameMatch && !descMatch { return false }
        }
        return true
    }

    private func lookupMilestoneByDisplayId(
        _ displayId: Int, args: [String: Any], projectFilter: UUID?
    ) -> MCPToolResult {
        do {
            let milestone = try milestoneService.findByDisplayID(displayId)
            guard milestoneMatches(milestone, args: args, projectFilter: projectFilter) else {
                return textResult(IntentHelpers.encodeJSONArray([]))
            }
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
        // Reject malformed or non-string projectId when the key is present
        // [T-665, T-788].
        switch parseProjectIdArgument(args) {
        case .failure(.message(let message)): return .error(message)
        case .success(let pid?): return .resolved(pid)
        case .success(nil):
            // Reject non-string `project` filter [T-1116].
            if args["project"] != nil, !(args["project"] is String) {
                return .error("project must be a string")
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
        let description: FieldChange<String>
        var hasChanges: Bool {
            if case .noChange = description {
                return status != nil || name != nil
            }
            return true
        }
    }

    private enum MilestoneValidation {
        case valid(ValidatedMilestoneUpdate)
        case invalid(MCPToolResult)
    }

    private func validateMilestoneUpdate(
        _ args: [String: Any], milestone: Milestone
    ) -> MilestoneValidation {
        // When the key is present it MUST be a string — a non-string value (e.g. integer,
        // boolean, null) would otherwise be silently dropped by `as? String`, letting other
        // update fields (name, description) apply with the malformed status quietly ignored [T-830].
        var newStatus: MilestoneStatus?
        if args["status"] != nil {
            guard let statusRaw = args["status"] as? String else {
                return .invalid(errorResult("status must be a string"))
            }
            guard let parsed = MilestoneStatus(rawValue: statusRaw) else {
                let valid = MilestoneStatus.allCases.map(\.rawValue).joined(separator: ", ")
                return .invalid(errorResult("Invalid status: \(statusRaw). Must be one of: \(valid)"))
            }
            newStatus = parsed
        }

        // Validate name. When the key is present it MUST be a string — a non-string
        // value (integer, boolean, null, array) would otherwise be silently dropped
        // by `as? String`, letting other update fields apply with the malformed
        // rename quietly ignored [T-1230].
        var trimmedName: String?
        if let rawName = args["name"] {
            guard let newName = rawName as? String else {
                return .invalid(errorResult("name must be a string"))
            }
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

        // Validate description. Same reasoning as name: a present-but-non-string
        // value must be rejected rather than silently dropped [T-1230]. An empty
        // or whitespace-only string is an explicit clear signal that sets the
        // description back to nil, mirroring update_task's clear semantics [T-1555].
        let newDescription: FieldChange<String>
        if let rawDescription = args["description"] {
            guard let descriptionString = rawDescription as? String else {
                return .invalid(errorResult("description must be a string"))
            }
            let trimmed = descriptionString.trimmingCharacters(in: .whitespacesAndNewlines)
            newDescription = trimmed.isEmpty ? .clear : .set(trimmed)
        } else {
            newDescription = .noChange
        }

        return .valid(ValidatedMilestoneUpdate(
            status: newStatus, name: trimmedName, description: newDescription
        ))
    }

    private func applyMilestoneUpdate(_ update: ValidatedMilestoneUpdate, to milestone: Milestone) {
        // T-923: Skip timestamp writes when the requested status matches the
        // current status so same-status retries don't rewrite completion dates.
        if let newStatus = update.status, milestone.statusRawValue != newStatus.rawValue {
            milestone.statusRawValue = newStatus.rawValue
            milestone.lastStatusChangeDate = Date.now
            milestone.completionDate = newStatus.isTerminal ? Date.now : nil
        }
        if let name = update.name {
            milestone.name = name
        }
        switch update.description {
        case .noChange:
            break
        case .set(let value):
            milestone.milestoneDescription = value
        case .clear:
            milestone.milestoneDescription = nil
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

    /// Updates one or more mutable fields on a task in a single atomic call.
    ///
    /// Field validation, milestone resolution, and applier logic are delegated
    /// to `TaskUpdateValidator` so that the MCP tool and `UpdateTaskIntent`
    /// share identical semantics. The identifier-resolution preamble preserves
    /// the existing T-634/T-808 behavior — present-but-malformed identifiers
    /// surface as field-specific INVALID_INPUT messages, not as a generic
    /// not-found. The response shape is built by
    /// `IntentHelpers.taskUpdateResponseDict` (AC 9.1).
    private func handleUpdateTask(_ args: [String: Any]) -> MCPToolResult {
        // Identifier resolution (preserve existing T-634 / T-808 behavior)
        // Reject non-integer displayId when key is present [T-634]
        if args["displayId"] != nil, IntentHelpers.parseIntValue(args["displayId"]) == nil {
            return errorResult("displayId must be an integer")
        }

        let task: TransitTask
        do {
            task = try taskService.resolveTask(from: args)
        } catch TaskService.Error.invalidIdentifier(let field) {
            // Reject malformed identifiers with a field-specific message
            // instead of returning the generic not-found error. [T-808]
            return errorResult(IntentHelpers.invalidIdentifierHint(for: field))
        } catch {
            return errorResult("Provide either displayId (integer) or taskId (UUID string)")
        }

        // Validate every field before applying any change. The validator is
        // pure — no mutations occur on success or failure, so an early return
        // here leaves the task untouched.
        let update: ValidatedTaskUpdate
        switch TaskUpdateValidator.validate(args, task: task, milestoneService: milestoneService) {
        case .success(let validated):
            update = validated
        case .failure(let error):
            return errorResult(error.mcpMessage)
        }

        // No-op echo: when the request includes only an identifier (and no
        // mutating field), skip the save and return the current task JSON.
        guard update.hasChanges else {
            return textResult(IntentHelpers.encodeJSON(IntentHelpers.taskUpdateResponseDict(task)))
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
            return errorResult("Update failed: \(error)")
        }

        // Save. `TaskService.save()` already calls `safeRollback()` on failure.
        do {
            try taskService.save()
        } catch {
            return errorResult("Update failed: \(error)")
        }

        return textResult(IntentHelpers.encodeJSON(IntentHelpers.taskUpdateResponseDict(task)))
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
        } catch TaskService.Error.invalidIdentifier(let field) {
            // Reject malformed identifiers with a field-specific message
            // instead of returning the generic not-found error. [T-808]
            return errorResult(IntentHelpers.invalidIdentifierHint(for: field))
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

    /// Validates the `arguments` envelope of a `tools/call` request. Omitting the
    /// key is allowed and yields `[:]` for tools whose inputs are all optional.
    /// A present-but-non-object value (string, array, number, boolean, null)
    /// must be rejected with `invalidParams` rather than silently coerced to
    /// `[:]` — otherwise read tools like `query_tasks` would execute with no
    /// filters and expose all data, while mutation tools would degrade to
    /// misleading "missing required field" errors [T-1247].
    private func parseArgumentsEnvelope(_ params: [String: Any]) -> Result<[String: Any], ResolveError> {
        guard params["arguments"] != nil else { return .success([:]) }
        guard let dict = params["arguments"] as? [String: Any] else {
            return .failure(.message("Invalid arguments: must be a JSON object"))
        }
        return .success(dict)
    }

    /// Validates a UUID-shaped argument by key. Returns `.success(nil)` when the
    /// key is absent, `.success(uuid)` when the value is a valid UUID string,
    /// or `.failure(.message(...))` when the key is present but the value is not
    /// a valid UUID string (covers non-string types too) [T-743, T-788].
    private func parseProjectIdArgument(_ args: [String: Any]) -> Result<UUID?, ResolveError> {
        guard args["projectId"] != nil else { return .success(nil) }
        guard let pidStr = args["projectId"] as? String, let pid = UUID(uuidString: pidStr) else {
            return .failure(.message("Invalid projectId: expected a UUID string"))
        }
        return .success(pid)
    }

    /// Validate that all values for a given key are valid raw values of the specified enum.
    /// Returns an error result if any value is invalid, or nil if all are valid (or the key is absent).
    ///
    /// When `allowArray` is true (the default), both array and single-string inputs are accepted —
    /// used for multi-value filters like `status`/`not_status`. When false, only a single string is
    /// accepted and an array is rejected — used for single-value filters like `type`, whose schema
    /// declares a single string enum and whose caller reads it back with `args["type"] as? String`.
    /// Accepting an array there would pass validation and then be silently dropped to `nil`,
    /// returning unfiltered results. [T-1404]
    ///
    /// If the key is present but the value is neither a String nor a [String] (e.g. a number,
    /// boolean, dictionary, or array containing non-string elements), this returns a
    /// field-specific error so malformed shapes cannot be silently treated as absent. [T-809, T-830]
    private func validateEnumFilter<E: RawRepresentable & CaseIterable>(
        _ args: [String: Any], key: String, type: E.Type, allowArray: Bool = true
    ) -> MCPToolResult? where E.RawValue == String {
        guard let raw = args[key] else { return nil }

        let expectation = allowArray ? "a string or array of strings" : "a string"

        let values: [String]
        if let single = raw as? String {
            values = [single]
        } else if allowArray, let array = raw as? [String] {
            values = array
        } else if allowArray, let anyArray = raw as? [Any] {
            // Reject arrays that contain non-string elements (e.g. ["idea", 123]).
            // `raw as? [String]` returns nil for mixed-type arrays, so we must inspect
            // the elements explicitly to distinguish "valid string array" from "mixed".
            let strings = anyArray.compactMap { $0 as? String }
            guard strings.count == anyArray.count else {
                return errorResult("Invalid \(key): expected \(expectation)")
            }
            values = strings
        } else {
            return errorResult("Invalid \(key): expected \(expectation)")
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
        } else if args["milestoneId"] != nil {
            // Validate type and UUID format separately from presence [T-769, T-810]
            guard let idStr = args["milestoneId"] as? String,
                  let milestoneId = UUID(uuidString: idStr) else {
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
                    "taskId": task.id.uuidString,
                    "name": task.name,
                    "status": task.statusRawValue,
                    "type": task.typeRawValue,
                    // Effective-priority invariant (Req 1.4): computed accessor, NOT priorityRawValue.
                    "priority": task.priority.rawValue
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
