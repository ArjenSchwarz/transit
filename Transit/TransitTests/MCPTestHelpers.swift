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
    let writeCoordinator: MCPWriteCoordinator
    let sidecarDirectory: URL
}

@MainActor
enum MCPTestHelpers {

    // swiftlint:disable:next function_body_length
    static func makeEnv(
        taskCreateSave: ((ModelContext) throws -> Void)? = nil,
        taskStatusSave: ((ModelContext) throws -> Void)? = nil,
        writeCommitSave: ((ModelContext) throws -> Void)? = nil,
        projectFetcher: (any ModelFetching)? = nil,
        taskFetcher: (any TaskFetching)? = nil,
        commentFetcher: (any CommentFetching)? = nil,
        milestoneFetcher: (any MilestoneFetching)? = nil,
        milestoneDisplayIDFinder: (any MilestoneDisplayIDFinding)? = nil,
        milestoneServiceFetcher: (any ModelFetching)? = nil,
        taskCounterStore: (any DisplayIDAllocator.CounterStore)? = nil,
        persistence: PersistenceAvailability? = nil
    ) throws -> MCPTestEnv {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let taskStore: any DisplayIDAllocator.CounterStore = taskCounterStore ?? InMemoryCounterStore()
        let taskAllocator = DisplayIDAllocator(store: taskStore)
        let taskService = TaskService(
            modelContext: context,
            displayIDAllocator: taskAllocator,
            createSave: taskCreateSave ?? { try $0.save() },
            statusSave: taskStatusSave ?? { try $0.save() }
        )
        let projectService = ProjectService(modelContext: context, fetcher: projectFetcher)
        let commentService = CommentService(modelContext: context)
        let milestoneStore = InMemoryCounterStore()
        let milestoneAllocator = DisplayIDAllocator(store: milestoneStore)
        let milestoneService = MilestoneService(
            modelContext: context,
            displayIDAllocator: milestoneAllocator,
            fetcher: milestoneServiceFetcher
        )
        let maintenanceService = DisplayIDMaintenanceService(
            modelContext: context,
            taskAllocator: taskAllocator,
            milestoneAllocator: milestoneAllocator,
            commentService: commentService
        )
        let mcpSettings = MCPSettings()
        // Default to off so existing tests don't see maintenance tools unless they opt in.
        mcpSettings.maintenanceToolsEnabled = false
        let sidecar = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let writeCoordinator = MCPWriteCoordinator(
            services: MCPWriteCommandServices(tasks: taskService, projects: projectService,
                comments: commentService, milestones: milestoneService, context: context),
            sidecarDirectory: sidecar, persistence: persistence,
            save: { context, stage in
                if case .commit = stage, let injectedSave = writeCommitSave ?? taskCreateSave ?? taskStatusSave {
                    try injectedSave(context)
                } else {
                    try context.save()
                }
            }
        )
        let handler = MCPToolHandler(
            taskService: taskService, projectService: projectService,
            commentService: commentService, milestoneService: milestoneService,
            maintenanceService: maintenanceService, settings: mcpSettings, persistence: persistence,
            taskFetcher: taskFetcher, commentFetcher: commentFetcher,
            milestoneFetcher: milestoneFetcher,
            milestoneDisplayIDFinder: milestoneDisplayIDFinder, writeCoordinator: writeCoordinator,
            batchContainer: context.container
        )
        return MCPTestEnv(
            handler: handler,
            taskService: taskService,
            projectService: projectService,
            commentService: commentService,
            milestoneService: milestoneService,
            maintenanceService: maintenanceService,
            mcpSettings: mcpSettings,
            context: context, writeCoordinator: writeCoordinator, sidecarDirectory: sidecar
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

    static func decodeQueryResults(_ response: JSONRPCResponse?) throws -> [[String: Any]] {
        try #require(decodeResult(response)["results"] as? [[String: Any]])
    }

    static func queryErrorMessage(_ response: JSONRPCResponse?) throws -> String {
        let error = try #require(decodeResult(response)["error"] as? [String: Any])
        return try #require(error["message"] as? String)
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
        let text = try #require(content.first?["text"] as? String)
        if let bytes = text.data(using: .utf8),
           let envelope = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           let error = envelope["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return text
    }

    /// Decodes the JSON-RPC `error` object from a response. Use this for cases
    /// where the handler rejects the request at the JSON-RPC envelope level
    /// (e.g. `invalidParams`) rather than returning a tool error result.
    static func jsonRPCError(_ response: JSONRPCResponse?) throws -> [String: Any] {
        let unwrapped = try #require(response, "Expected a JSON-RPC response but got nil")
        let data = try JSONEncoder().encode(unwrapped)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["error"] as? [String: Any])
    }
}

#endif
