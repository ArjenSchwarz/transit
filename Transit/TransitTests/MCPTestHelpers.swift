#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

struct MCPTestEnv {
    let handler: MCPToolHandler
    let taskService: TaskService
    let projectService: ProjectService
    let commentService: CommentService
    let milestoneService: MilestoneService
    let maintenanceService: DisplayIDMaintenanceService
    let mcpSettings: MCPSettings
    let context: ModelContext
}

@MainActor
enum MCPTestHelpers {

    static func makeEnv() throws -> MCPTestEnv {
        let context = try TestModelContainer.newContext()
        let taskStore = InMemoryCounterStore()
        let taskAllocator = DisplayIDAllocator(store: taskStore)
        let taskService = TaskService(modelContext: context, displayIDAllocator: taskAllocator)
        let projectService = ProjectService(modelContext: context)
        let commentService = CommentService(modelContext: context)
        let milestoneStore = InMemoryCounterStore()
        let milestoneAllocator = DisplayIDAllocator(store: milestoneStore)
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator)
        let maintenanceService = DisplayIDMaintenanceService(
            modelContext: context,
            taskAllocator: taskAllocator,
            taskCounterStore: taskStore,
            milestoneAllocator: milestoneAllocator,
            milestoneCounterStore: milestoneStore,
            commentService: commentService
        )
        let mcpSettings = MCPSettings()
        // Default to off so existing tests don't see maintenance tools unless they opt in.
        mcpSettings.maintenanceToolsEnabled = false
        let handler = MCPToolHandler(
            taskService: taskService, projectService: projectService,
            commentService: commentService, milestoneService: milestoneService,
            maintenanceService: maintenanceService, settings: mcpSettings
        )
        return MCPTestEnv(
            handler: handler,
            taskService: taskService,
            projectService: projectService,
            commentService: commentService,
            milestoneService: milestoneService,
            maintenanceService: maintenanceService,
            mcpSettings: mcpSettings,
            context: context
        )
    }

    @discardableResult
    static func makeProject(
        in context: ModelContext, name: String = "Test Project", gitRepo: String? = nil
    ) -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: gitRepo, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    static func request(method: String, id: Int = 1, params: [String: Any]? = nil) -> JSONRPCRequest {
        let paramsValue = params.map { AnyCodable($0) }
        return JSONRPCRequest(jsonrpc: "2.0", id: .integer(id), method: method, params: paramsValue)
    }

    static func toolCallRequest(tool: String, arguments: [String: Any], id: Int = 1) -> JSONRPCRequest {
        request(method: "tools/call", id: id, params: ["name": tool, "arguments": arguments])
    }

    static func decodeResult(_ response: JSONRPCResponse?) throws -> [String: Any] {
        let unwrapped = try #require(response, "Expected a JSON-RPC response but got nil")
        let data = try JSONEncoder().encode(unwrapped)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = try #require(json?["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let textData = try #require(text.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: textData) as? [String: Any])
    }

    static func decodeArrayResult(_ response: JSONRPCResponse?) throws -> [[String: Any]] {
        let unwrapped = try #require(response, "Expected a JSON-RPC response but got nil")
        let data = try JSONEncoder().encode(unwrapped)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = try #require(json?["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let textData = try #require(text.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: textData) as? [[String: Any]])
    }

    static func isError(_ response: JSONRPCResponse?) throws -> Bool {
        let unwrapped = try #require(response, "Expected a JSON-RPC response but got nil")
        let data = try JSONEncoder().encode(unwrapped)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = try #require(json?["result"] as? [String: Any])
        return result["isError"] as? Bool == true
    }

    static func errorText(_ response: JSONRPCResponse?) throws -> String {
        let unwrapped = try #require(response, "Expected a JSON-RPC response but got nil")
        let data = try JSONEncoder().encode(unwrapped)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = try #require(json?["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        return try #require(content.first?["text"] as? String)
    }
}

#endif
