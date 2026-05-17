#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1116: When `project` (name filter) is present but not a String — for example
// a JSON number, boolean, array, or object — the query handlers must reject the
// input with `project must be a string` instead of silently dropping the filter
// and returning every matching task or milestone. Mirrors the T-788 pattern for
// non-string `projectId`.
@MainActor @Suite(.serialized)
struct MCPNonStringProjectNameTests {

    // MARK: - query_tasks

    @Test func queryTasksNumericProjectNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .bug, project: alpha
        )

        // Numeric `project` must not fall through to "no filter applied".
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": 123]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func queryTasksBooleanProjectNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .bug, project: alpha
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": true]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func queryTasksArrayProjectNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .bug, project: alpha
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": ["Alpha"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    // MARK: - query_milestones

    @Test func queryMilestonesNumericProjectNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: alpha
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["project": 123]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func queryMilestonesBooleanProjectNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: alpha
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["project": false]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    @Test func queryMilestonesArrayProjectNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: alpha
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["project": ["Alpha"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("project") && errorMessage.contains("string"))
    }

    // MARK: - Whitespace preservation

    @Test func queryTasksEmptyProjectNameStillReturnsAllTasks() async throws {
        // Existing behaviour: whitespace-only project is treated as "no filter".
        // This test guards against an over-strict fix that breaks that path.
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
}

#endif
