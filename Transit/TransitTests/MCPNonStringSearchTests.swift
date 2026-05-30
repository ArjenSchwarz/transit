#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1156: When `search` is present but not a String — for example a JSON number,
// boolean, array, or object — the query handlers must reject the input with
// `search must be a string` instead of silently dropping the filter via
// `as? String` and returning every task or milestone. Mirrors the T-1116
// pattern for non-string `project`.
@MainActor @Suite(.serialized)
struct MCPNonStringSearchTests {

    // MARK: - query_tasks

    @Test func queryTasksNumericSearchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .bug, project: project
        )

        // Numeric `search` must not fall through to "no filter applied".
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": 123]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("search") && errorMessage.contains("string"))
    }

    @Test func queryTasksBooleanSearchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": true]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("search") && errorMessage.contains("string"))
    }

    @Test func queryTasksArraySearchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": ["login"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("search") && errorMessage.contains("string"))
    }

    // MARK: - query_milestones

    @Test func queryMilestonesNumericSearchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: alpha
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["search": 123]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("search") && errorMessage.contains("string"))
    }

    @Test func queryMilestonesBooleanSearchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: alpha
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["search": false]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("search") && errorMessage.contains("string"))
    }

    @Test func queryMilestonesArraySearchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: alpha
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["search": ["v1"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("search") && errorMessage.contains("string"))
    }

    // MARK: - Whitespace preservation (guard against over-strict fix)

    @Test func queryTasksWhitespaceSearchStillReturnsAllTasks() async throws {
        // Existing behaviour: whitespace-only search is treated as "no filter".
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "A", description: nil, type: .feature, project: project)
        _ = try await env.taskService.createTask(name: "B", description: nil, type: .bug, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": "  "]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)
    }
}

#endif
