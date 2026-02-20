#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPToolHandlerTests {

    // MARK: - Initialize

    @Test func initializeReturnsServerInfo() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = try #require(await env.handler.handle(MCPTestHelpers.request(method: "initialize")))

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

    @Test func toolsListReturnsFiveTools() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = try #require(await env.handler.handle(MCPTestHelpers.request(method: "tools/list")))

        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(json["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])

        #expect(tools.count == 5)
        let names = tools.compactMap { $0["name"] as? String }
        #expect(names.contains("create_task"))
        #expect(names.contains("update_task_status"))
        #expect(names.contains("query_tasks"))
        #expect(names.contains("add_comment"))
        #expect(names.contains("get_projects"))
    }

    // MARK: - Ping

    @Test func pingReturnsSuccess() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = try #require(await env.handler.handle(MCPTestHelpers.request(method: "ping")))

        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["result"] != nil)
        #expect(json["error"] == nil)
    }

    // MARK: - Unknown Method

    @Test func unknownMethodReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = try #require(await env.handler.handle(MCPTestHelpers.request(method: "foo/bar")))

        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = try #require(json["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32601)
    }

    // MARK: - create_task

    @Test func createTaskSuccess() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "New Task",
                "type": "feature",
                "projectId": project.id.uuidString
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["taskId"] is String)
        #expect(result["status"] as? String == "idea")
        #expect(result["displayId"] as? Int == 1)
    }

    @Test func createTaskMissingNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["type": "bug"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func createTaskInvalidTypeReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["name": "Task", "type": "epic", "projectId": project.id.uuidString]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func createTaskByProjectName() async throws {
        let env = try MCPTestHelpers.makeEnv()
        MCPTestHelpers.makeProject(in: env.context, name: "Alpha")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["name": "Task", "type": "bug", "project": "Alpha"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["status"] as? String == "idea")
    }

    @Test func createTaskUnknownProjectReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["name": "Task", "type": "bug", "project": "Nonexistent"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    // MARK: - update_task_status

    @Test func updateStatusByDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 1, "status": "planning"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["previousStatus"] as? String == "idea")
        #expect(result["status"] as? String == "planning")
    }

    @Test func updateStatusByTaskId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["taskId": task.id.uuidString, "status": "in-progress"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["previousStatus"] as? String == "idea")
        #expect(result["status"] as? String == "in-progress")
    }

    @Test func updateStatusMissingStatusReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 1]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func updateStatusTaskNotFoundReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 999, "status": "done"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    // MARK: - query_tasks

    @Test func queryAllTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "A", description: nil, type: .feature, project: project)
        _ = try await env.taskService.createTask(name: "B", description: nil, type: .bug, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)
    }

    @Test func queryTasksFilterByStatus() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "A", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: task, to: .planning)
        _ = try await env.taskService.createTask(name: "B", description: nil, type: .bug, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": "planning"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "A")
    }

    @Test func queryTasksFilterByType() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "Bug", description: nil, type: .bug, project: project)
        _ = try await env.taskService.createTask(name: "Feature", description: nil, type: .feature, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["type": "bug"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Bug")
    }

    @Test func queryTasksReturnsProjectInfo() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.taskService.createTask(name: "Task", description: nil, type: .feature, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let first = try #require(results.first)
        #expect(first["projectName"] as? String == "Alpha")
        #expect(first["projectId"] is String)
    }

    // MARK: - get_projects

    @Test func getProjectsReturnsCorrectFieldsAndSortOrder() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let bravo = MCPTestHelpers.makeProject(in: env.context, name: "Bravo")
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.taskService.createTask(name: "T1", description: nil, type: .feature, project: alpha)
        _ = try await env.taskService.createTask(name: "T2", description: nil, type: .bug, project: bravo)
        _ = try await env.taskService.createTask(name: "T3", description: nil, type: .chore, project: bravo)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "get_projects", arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)

        let first = try #require(results.first)
        #expect(first["name"] as? String == "Alpha")
        #expect(first["projectId"] is String)
        #expect(first["description"] is String)
        #expect(first["colorHex"] is String)
        #expect(first["activeTaskCount"] as? Int == 1)

        let second = try #require(results.last)
        #expect(second["name"] as? String == "Bravo")
        #expect(second["activeTaskCount"] as? Int == 2)
    }

    @Test func getProjectsReturnsEmptyArrayWhenNoProjects() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "get_projects", arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    @Test func getProjectsActiveTaskCountExcludesTerminalTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let doneTask = try await env.taskService.createTask(
            name: "Done", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: doneTask, to: .done)
        let abandonedTask = try await env.taskService.createTask(
            name: "Abandoned", description: nil, type: .bug, project: project
        )
        try env.taskService.updateStatus(task: abandonedTask, to: .abandoned)
        _ = try await env.taskService.createTask(
            name: "Active", description: nil, type: .chore, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "get_projects", arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let first = try #require(results.first)
        #expect(first["activeTaskCount"] as? Int == 1)
    }
}

#endif
