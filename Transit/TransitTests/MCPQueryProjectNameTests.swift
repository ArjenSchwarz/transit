#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPQueryProjectNameTests {

    @Test func queryByProjectNameReturnsMatchingTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let beta = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        _ = try await env.taskService.createTask(name: "A1", description: nil, type: .feature, project: alpha)
        _ = try await env.taskService.createTask(name: "B1", description: nil, type: .bug, project: beta)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "Alpha"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "A1")
    }

    @Test func queryByProjectNameIsCaseInsensitive() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context, name: "MyProject")
        _ = try await env.taskService.createTask(name: "Task", description: nil, type: .chore, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "myproject"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
    }

    @Test func queryByUnknownProjectNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "Nonexistent"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func queryWithProjectIdAndProjectNameUsesProjectId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let beta = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        _ = try await env.taskService.createTask(name: "A1", description: nil, type: .feature, project: alpha)
        _ = try await env.taskService.createTask(name: "B1", description: nil, type: .bug, project: beta)

        // projectId points to Beta, project name says "Alpha" — projectId wins
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["projectId": beta.id.uuidString, "project": "Alpha"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "B1")
    }

    @Test func queryWithEmptyProjectNameReturnsAllTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "A", description: nil, type: .feature, project: project)
        _ = try await env.taskService.createTask(name: "B", description: nil, type: .bug, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "  "]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)
    }

    @Test func queryByProjectNameCombinedWithStatusFilter() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let task = try await env.taskService.createTask(
            name: "Planned", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: task, to: .planning)
        _ = try await env.taskService.createTask(name: "Idea", description: nil, type: .bug, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "Alpha", "status": "planning"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Planned")
    }

    @Test func queryByProjectNameCombinedWithTypeFilter() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.taskService.createTask(name: "Bug", description: nil, type: .bug, project: project)
        _ = try await env.taskService.createTask(name: "Feature", description: nil, type: .feature, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "Alpha", "type": "bug"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Bug")
    }
}

#endif
