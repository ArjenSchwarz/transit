#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// MCP `create_task` / `query_tasks` priority coverage (Req 5.1, 5.3, 5.4, 5.5).
/// Priority filtering is multi-value on the MCP surface (mirrors `status`), and
/// every serialized task echoes its effective priority through the computed
/// accessor (Req 1.4).
@MainActor @Suite(.serialized)
struct MCPPriorityTests {

    // MARK: - create_task

    @Test func createTaskDefaultsToMediumAndEchoesIt() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["name": "Task", "type": "feature", "projectId": project.id.uuidString]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["priority"] as? String == "medium")
    }

    @Test func createTaskHonorsExplicitPriority() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task", "type": "feature",
                "projectId": project.id.uuidString, "priority": "high"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["priority"] as? String == "high")

        // The created task itself must carry the requested priority.
        let tasks = try env.taskService.fetchAllTasks()
        #expect(tasks.count == 1)
        #expect(tasks.first?.priority == .high)
    }

    @Test func createTaskInvalidPriorityReturnsErrorAndCreatesNoTask() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task", "type": "feature",
                "projectId": project.id.uuidString, "priority": "urgent"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let message = try MCPTestHelpers.errorText(response)
        #expect(message.contains("priority"))

        // Req 5.5: no task is created on a validation failure.
        let tasks = try env.taskService.fetchAllTasks()
        #expect(tasks.isEmpty)
    }

    // MARK: - query_tasks serialization (Req 5.3)

    @Test func queryReturnsPriorityForEachTask() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "High", description: nil, type: .feature, project: project, priority: .high
        )
        _ = try await env.taskService.createTask(
            name: "Default", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let byName = Dictionary(uniqueKeysWithValues: results.compactMap { dict -> (String, String)? in
            guard let name = dict["name"] as? String, let priority = dict["priority"] as? String else {
                return nil
            }
            return (name, priority)
        })
        #expect(byName["High"] == "high")
        #expect(byName["Default"] == "medium")
    }

    // MARK: - query_tasks filtering (Req 5.4)

    @Test func queryFiltersBySinglePriorityString() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "High", description: nil, type: .feature, project: project, priority: .high
        )
        _ = try await env.taskService.createTask(
            name: "Low", description: nil, type: .feature, project: project, priority: .low
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: ["priority": "high"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "High")
    }

    @Test func queryFiltersByPriorityArray() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "High", description: nil, type: .feature, project: project, priority: .high
        )
        _ = try await env.taskService.createTask(
            name: "Medium", description: nil, type: .feature, project: project, priority: .medium
        )
        _ = try await env.taskService.createTask(
            name: "Low", description: nil, type: .feature, project: project, priority: .low
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: ["priority": ["high", "low"]]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let names = Set(results.compactMap { $0["name"] as? String })
        #expect(names == ["High", "Low"])
    }

    @Test func queryWithoutPriorityFilterReturnsAllPriorities() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "High", description: nil, type: .feature, project: project, priority: .high
        )
        _ = try await env.taskService.createTask(
            name: "Low", description: nil, type: .feature, project: project, priority: .low
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)
    }

    @Test func queryInvalidPriorityFilterReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: ["priority": "urgent"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let message = try MCPTestHelpers.errorText(response)
        #expect(message.contains("priority"))
    }
}

#endif
