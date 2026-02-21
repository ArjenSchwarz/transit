#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPSearchFilterTests {

    @Test func searchByNameReturnsMatchingTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Fix login bug", description: nil, type: .bug, project: project
        )
        _ = try await env.taskService.createTask(
            name: "Add dashboard", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": "login"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Fix login bug")
    }

    @Test func searchByDescriptionReturnsMatchingTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task A", description: "Refactor the authentication module", type: .chore, project: project
        )
        _ = try await env.taskService.createTask(
            name: "Task B", description: "Update README", type: .documentation, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": "authentication"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Task A")
    }

    @Test func searchIsCaseInsensitive() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Fix Login Bug", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": "fix login"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
    }

    @Test func searchCombinesWithTypeFilter() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Fix login bug", description: nil, type: .bug, project: project
        )
        _ = try await env.taskService.createTask(
            name: "Login feature", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": "login", "type": "bug"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Fix login bug")
    }

    @Test func searchCombinesWithStatusFilter() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Fix login bug", description: nil, type: .bug, project: project
        )
        let task2 = try await env.taskService.createTask(
            name: "Fix logout bug", description: nil, type: .bug, project: project
        )
        try env.taskService.updateStatus(task: task2, to: .planning)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": "fix", "status": ["planning"]]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Fix logout bug")
    }

    @Test func whitespaceOnlySearchTreatedAsAbsent() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task A", description: nil, type: .feature, project: project
        )
        _ = try await env.taskService.createTask(
            name: "Task B", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": "   "]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)
    }

    @Test func searchWithNilDescriptionDoesNotCrash() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "No description task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": "something"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    @Test func searchMatchesNameOrDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Auth task", description: "Fix password reset", type: .bug, project: project
        )
        _ = try await env.taskService.createTask(
            name: "Update docs", description: "Auth flow documentation", type: .documentation, project: project
        )
        _ = try await env.taskService.createTask(
            name: "Unrelated", description: "Nothing relevant", type: .chore, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": "auth"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)
        let names = Set(results.compactMap { $0["name"] as? String })
        #expect(names == ["Auth task", "Update docs"])
    }

    @Test func searchWithDisplayIdMatchReturnsTask() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Fix login bug", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1, "search": "login"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Fix login bug")
    }

    @Test func searchWithDisplayIdNonMatchReturnsEmpty() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Fix login bug", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 1, "search": "dashboard"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    @Test func emptySearchStringReturnsAllTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task A", description: nil, type: .feature, project: project
        )
        _ = try await env.taskService.createTask(
            name: "Task B", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": ""]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)
    }
}

#endif
