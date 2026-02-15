#if os(macOS)
import Foundation
import SwiftData

@MainActor
final class MCPToolHandler {

    private let taskService: TaskService
    private let projectService: ProjectService
    private let commentService: CommentService

    init(taskService: TaskService, projectService: ProjectService, commentService: CommentService) {
        self.taskService = taskService
        self.projectService = projectService
        self.commentService = commentService
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
        let tools = MCPToolsListResult(tools: MCPToolDefinitions.all)
        return JSONRPCResponse.success(id: id, result: tools)
    }

    // MARK: - Tools Call

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
        default:
            return JSONRPCResponse.error(
                id: id,
                code: JSONRPCErrorCode.methodNotFound,
                message: "Unknown tool: \(name)"
            )
        }

        return JSONRPCResponse.success(id: id, result: result)
    }

    // MARK: - create_task

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

        let projectId = (args["projectId"] as? String).flatMap(UUID.init)
        let projectName = args["project"] as? String
        let project: Project
        switch projectService.findProject(id: projectId, name: projectName) {
        case .success(let found):
            project = found
        case .failure(let error):
            return errorResult(IntentHelpers.mapProjectLookupError(error).hint)
        }

        let task: TransitTask
        do {
            task = try await taskService.createTask(
                name: name,
                description: args["description"] as? String,
                type: taskType,
                project: project,
                metadata: stringMetadata(from: args["metadata"])
            )
        } catch {
            return errorResult("Task creation failed: \(error)")
        }

        var response: [String: Any] = [
            "taskId": task.id.uuidString,
            "status": task.statusRawValue
        ]
        if let displayId = task.permanentDisplayId {
            response["displayId"] = displayId
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

        let task: TransitTask
        switch resolveTask(from: args) {
        case .success(let found): task = found
        case .failure(.message(let message)): return errorResult(message)
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

    private func handleQueryTasks(_ args: [String: Any]) -> MCPToolResult {
        var projectFilter: UUID?
        if let pidStr = args["projectId"] as? String {
            guard let pid = UUID(uuidString: pidStr) else {
                return errorResult("Invalid projectId: expected a UUID string")
            }
            projectFilter = pid
        }

        let filters = QueryFilters(
            status: args["status"] as? String,
            type: args["type"] as? String,
            projectId: projectFilter
        )

        // Single-task lookup by displayId — returns early with detailed response
        if let displayId = args["displayId"] as? Int {
            return handleDisplayIdLookup(displayId, filters: filters)
        }

        // Full-table query
        let allTasks: [TransitTask]
        do {
            allTasks = try projectService.context.fetch(FetchDescriptor<TransitTask>())
        } catch {
            return errorResult("Failed to fetch tasks: \(error)")
        }

        let filtered = allTasks.filter { filters.matches($0) }
        let isoFormatter = ISO8601DateFormatter()
        let results = filtered.map { taskToDict($0, formatter: isoFormatter) }
        return textResult(IntentHelpers.encodeJSONArray(results))
    }

    private func handleDisplayIdLookup(_ displayId: Int, filters: QueryFilters) -> MCPToolResult {
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

// MARK: - add_comment & Helpers

extension MCPToolHandler {

    func handleAddComment(_ args: [String: Any]) -> MCPToolResult {
        guard let content = args["content"] as? String, !content.isEmpty else {
            return errorResult("Missing required argument: content")
        }
        guard let authorName = args["authorName"] as? String, !authorName.isEmpty else {
            return errorResult("Missing required argument: authorName")
        }

        let task: TransitTask
        switch resolveTask(from: args) {
        case .success(let found): task = found
        case .failure(.message(let message)): return errorResult(message)
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

    func resolveTask(from args: [String: Any]) -> Result<TransitTask, ResolveError> {
        if let displayId = args["displayId"] as? Int {
            do {
                return .success(try taskService.findByDisplayID(displayId))
            } catch {
                return .failure(.message("No task with displayId \(displayId)"))
            }
        } else if let idStr = args["taskId"] as? String, let taskId = UUID(uuidString: idStr) {
            do {
                return .success(try taskService.findByID(taskId))
            } catch {
                return .failure(.message("No task with taskId \(idStr)"))
            }
        } else {
            return .failure(.message("Provide either displayId (integer) or taskId (UUID string)"))
        }
    }

    func textResult(_ text: String) -> MCPToolResult { MCPToolResult(content: [.text(text)], isError: nil) }
    func errorResult(_ message: String) -> MCPToolResult { MCPToolResult(content: [.text(message)], isError: true) }

    func stringMetadata(from value: Any?) -> [String: String]? {
        guard let dict = value as? [String: Any] else { return nil }
        var result: [String: String] = [:]
        for (key, val) in dict { result[key] = "\(val)" }
        return result.isEmpty ? nil : result
    }

    func taskToDict(_ task: TransitTask, formatter: ISO8601DateFormatter, detailed: Bool = false) -> [String: Any] {
        var dict: [String: Any] = [
            "taskId": task.id.uuidString, "name": task.name,
            "status": task.statusRawValue, "type": task.typeRawValue,
            "lastStatusChangeDate": formatter.string(from: task.lastStatusChangeDate)
        ]
        if let displayId = task.permanentDisplayId { dict["displayId"] = displayId }
        if let projectId = task.project?.id.uuidString { dict["projectId"] = projectId }
        if let projectName = task.project?.name { dict["projectName"] = projectName }
        if let completionDate = task.completionDate { dict["completionDate"] = formatter.string(from: completionDate) }
        if detailed {
            dict["description"] = task.taskDescription as Any
            if !task.metadata.isEmpty { dict["metadata"] = task.metadata }
        }
        let comments = (try? commentService.fetchComments(for: task.id)) ?? []
        dict["comments"] = comments.map { [
            "id": $0.id.uuidString, "authorName": $0.authorName, "content": $0.content,
            "isAgent": $0.isAgent, "creationDate": formatter.string(from: $0.creationDate)
        ] as [String: Any] }
        return dict
    }
}

// MARK: - Query Filters

private struct QueryFilters {
    let status: String?
    let type: String?
    let projectId: UUID?

    func matches(_ task: TransitTask) -> Bool {
        if let status, task.statusRawValue != status { return false }
        if let type, task.typeRawValue != type { return false }
        if let projectId, task.project?.id != projectId { return false }
        return true
    }
}

private nonisolated struct EmptyResult: Encodable, Sendable {}

#endif
