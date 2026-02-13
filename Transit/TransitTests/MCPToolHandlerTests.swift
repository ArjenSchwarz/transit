#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPToolHandlerTests {

    // MARK: - Helpers

    private struct Env {
        let handler: MCPToolHandler
        let taskService: TaskService
        let projectService: ProjectService
        let context: ModelContext
    }

    private func makeEnv() throws -> Env {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        let handler = MCPToolHandler(taskService: taskService, projectService: projectService)
        return Env(handler: handler, taskService: taskService, projectService: projectService, context: context)
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    private func request(method: String, id: Int = 1, params: [String: Any]? = nil) -> JSONRPCRequest {
        let paramsValue = params.map { AnyCodable($0) }
        return JSONRPCRequest(jsonrpc: "2.0", id: .integer(id), method: method, params: paramsValue)
    }

    private func toolCallRequest(tool: String, arguments: [String: Any], id: Int = 1) -> JSONRPCRequest {
        request(method: "tools/call", id: id, params: ["name": tool, "arguments": arguments])
    }

    private func decodeResult(_ response: JSONRPCResponse?) throws -> [String: Any] {
        let unwrapped = try #require(response, "Expected a JSON-RPC response but got nil")
        let data = try JSONEncoder().encode(unwrapped)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = try #require(json?["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let textData = try #require(text.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: textData) as? [String: Any])
    }

    private func decodeArrayResult(_ response: JSONRPCResponse?) throws -> [[String: Any]] {
        let unwrapped = try #require(response, "Expected a JSON-RPC response but got nil")
        let data = try JSONEncoder().encode(unwrapped)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = try #require(json?["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let textData = try #require(text.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: textData) as? [[String: Any]])
    }

    private func isError(_ response: JSONRPCResponse?) throws -> Bool {
        let unwrapped = try #require(response, "Expected a JSON-RPC response but got nil")
        let data = try JSONEncoder().encode(unwrapped)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = try #require(json?["result"] as? [String: Any])
        return result["isError"] as? Bool == true
    }

    // MARK: - Initialize

    @Test func initializeReturnsServerInfo() async throws {
        let env = try makeEnv()
        let response = try #require(await env.handler.handle(request(method: "initialize")))

        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(json["result"] as? [String: Any])

        #expect(result["protocolVersion"] as? String == "2025-03-26")
        let serverInfo = try #require(result["serverInfo"] as? [String: Any])
        #expect(serverInfo["name"] as? String == "transit")
        let capabilities = try #require(result["capabilities"] as? [String: Any])
        #expect(capabilities["tools"] is [String: Any])
    }

    // MARK: - Tools List

    @Test func toolsListReturnsThreeTools() async throws {
        let env = try makeEnv()
        let response = try #require(await env.handler.handle(request(method: "tools/list")))

        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(json["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])

        #expect(tools.count == 3)
        let names = tools.compactMap { $0["name"] as? String }
        #expect(names.contains("create_task"))
        #expect(names.contains("update_task_status"))
        #expect(names.contains("query_tasks"))
    }

    // MARK: - Ping

    @Test func pingReturnsSuccess() async throws {
        let env = try makeEnv()
        let response = try #require(await env.handler.handle(request(method: "ping")))

        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["result"] != nil)
        #expect(json["error"] == nil)
    }

    // MARK: - Unknown Method

    @Test func unknownMethodReturnsError() async throws {
        let env = try makeEnv()
        let response = try #require(await env.handler.handle(request(method: "foo/bar")))

        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = try #require(json["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32601)
    }

    // MARK: - create_task

    @Test func createTaskSuccess() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)

        let response = await env.handler.handle(toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "New Task",
                "type": "feature",
                "projectId": project.id.uuidString
            ]
        ))

        let result = try decodeResult(response)
        #expect(result["taskId"] is String)
        #expect(result["status"] as? String == "idea")
        #expect(result["displayId"] as? Int == 1)
    }

    @Test func createTaskMissingNameReturnsError() async throws {
        let env = try makeEnv()

        let response = await env.handler.handle(toolCallRequest(
            tool: "create_task",
            arguments: ["type": "bug"]
        ))

        #expect(try isError(response))
    }

    @Test func createTaskInvalidTypeReturnsError() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)

        let response = await env.handler.handle(toolCallRequest(
            tool: "create_task",
            arguments: ["name": "Task", "type": "epic", "projectId": project.id.uuidString]
        ))

        #expect(try isError(response))
    }

    @Test func createTaskByProjectName() async throws {
        let env = try makeEnv()
        makeProject(in: env.context, name: "Alpha")

        let response = await env.handler.handle(toolCallRequest(
            tool: "create_task",
            arguments: ["name": "Task", "type": "bug", "project": "Alpha"]
        ))

        let result = try decodeResult(response)
        #expect(result["status"] as? String == "idea")
    }

    @Test func createTaskUnknownProjectReturnsError() async throws {
        let env = try makeEnv()

        let response = await env.handler.handle(toolCallRequest(
            tool: "create_task",
            arguments: ["name": "Task", "type": "bug", "project": "Nonexistent"]
        ))

        #expect(try isError(response))
    }

    // MARK: - update_task_status

    @Test func updateStatusByDisplayId() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 1, "status": "planning"]
        ))

        let result = try decodeResult(response)
        #expect(result["previousStatus"] as? String == "idea")
        #expect(result["status"] as? String == "planning")
    }

    @Test func updateStatusByTaskId() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(toolCallRequest(
            tool: "update_task_status",
            arguments: ["taskId": task.id.uuidString, "status": "in-progress"]
        ))

        let result = try decodeResult(response)
        #expect(result["previousStatus"] as? String == "idea")
        #expect(result["status"] as? String == "in-progress")
    }

    @Test func updateStatusMissingStatusReturnsError() async throws {
        let env = try makeEnv()

        let response = await env.handler.handle(toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 1]
        ))

        #expect(try isError(response))
    }

    @Test func updateStatusTaskNotFoundReturnsError() async throws {
        let env = try makeEnv()

        let response = await env.handler.handle(toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 999, "status": "done"]
        ))

        #expect(try isError(response))
    }

    // MARK: - query_tasks

    @Test func queryAllTasks() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "A", description: nil, type: .feature, project: project)
        _ = try await env.taskService.createTask(name: "B", description: nil, type: .bug, project: project)

        let response = await env.handler.handle(toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        let results = try decodeArrayResult(response)
        #expect(results.count == 2)
    }

    @Test func queryTasksFilterByStatus() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "A", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: task, to: .planning)
        _ = try await env.taskService.createTask(name: "B", description: nil, type: .bug, project: project)

        let response = await env.handler.handle(toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": "planning"]
        ))

        let results = try decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "A")
    }

    @Test func queryTasksFilterByType() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "Bug", description: nil, type: .bug, project: project)
        _ = try await env.taskService.createTask(name: "Feature", description: nil, type: .feature, project: project)

        let response = await env.handler.handle(toolCallRequest(
            tool: "query_tasks",
            arguments: ["type": "bug"]
        ))

        let results = try decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Bug")
    }

    @Test func queryTasksReturnsProjectInfo() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context, name: "Alpha")
        _ = try await env.taskService.createTask(name: "Task", description: nil, type: .feature, project: project)

        let response = await env.handler.handle(toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        let results = try decodeArrayResult(response)
        let first = try #require(results.first)
        #expect(first["projectName"] as? String == "Alpha")
        #expect(first["projectId"] is String)
    }
    // MARK: - query_tasks displayId

    @Test func queryByDisplayIdReturnsDetailedTask() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Lookup Me",
            description: "A detailed description",
            type: .bug,
            project: project,
            metadata: ["git.branch": "feature/test"]
        )

        let response = await env.handler.handle(toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1]
        ))

        let results = try decodeArrayResult(response)
        #expect(results.count == 1)
        let task = try #require(results.first)
        #expect(task["name"] as? String == "Lookup Me")
        #expect(task["description"] as? String == "A detailed description")
        let metadata = try #require(task["metadata"] as? [String: String])
        #expect(metadata["git.branch"] == "feature/test")
    }

    @Test func queryByDisplayIdNotFoundReturnsEmptyArray() async throws {
        let env = try makeEnv()

        let response = await env.handler.handle(toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 999]
        ))

        let results = try decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    @Test func queryByDisplayIdWithNonMatchingStatusReturnsEmpty() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Idea Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1, "status": "planning"]
        ))

        let results = try decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    @Test func queryByDisplayIdWithMatchingFilterReturnsTask() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Bug Task", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1, "type": "bug"]
        ))

        let results = try decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Bug Task")
    }

    @Test func queryByDisplayIdOmitsDescriptionWhenNil() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "No Desc", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1]
        ))

        let results = try decodeArrayResult(response)
        let task = try #require(results.first)
        // description key should be present but null (serialized as NSNull)
        #expect(task["name"] as? String == "No Desc")
        #expect(task.keys.contains("description"))
    }

    @Test func queryWithoutDisplayIdOmitsDescriptionAndMetadata() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Regular", description: "Has desc", type: .feature, project: project,
            metadata: ["key": "value"]
        )

        let response = await env.handler.handle(toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        let results = try decodeArrayResult(response)
        let task = try #require(results.first)
        #expect(task["description"] == nil)
        #expect(task["metadata"] == nil)
    }
}

#endif
