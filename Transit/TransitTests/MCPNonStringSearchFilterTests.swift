#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1266: Present-but-non-string string filters must be rejected with an
// INVALID_INPUT-style error instead of being silently dropped by `as? String`.
// A silently dropped filter broadens results unexpectedly — e.g.
// `query_tasks({"search": 42})` would return every task instead of an error,
// and `query_tasks({"milestone": 42})` would return unfiltered tasks instead of
// erroring. Mirrors the T-1116 (project) and T-1205 (comment) validation pattern.
@MainActor @Suite(.serialized)
struct MCPNonStringSearchFilterTests {

    // MARK: - query_tasks: search

    @Test func queryTasksNumericSearchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "A", description: nil, type: .bug, project: project)
        _ = try await env.taskService.createTask(name: "B", description: nil, type: .feature, project: project)

        // Numeric `search` must not fall through to "no filter applied" and return all tasks.
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": 42]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("search") && errorMessage.contains("string"))
    }

    @Test func queryTasksBooleanSearchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "A", description: nil, type: .bug, project: project)

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
        _ = try await env.taskService.createTask(name: "A", description: nil, type: .bug, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": ["login"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("search") && errorMessage.contains("string"))
    }

    // MARK: - query_tasks: milestone

    @Test func queryTasksNumericMilestoneReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        // One task assigned to the milestone, one without.
        let assigned = try await env.taskService.createTask(
            name: "Assigned", description: nil, type: .bug, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: assigned)
        _ = try await env.taskService.createTask(
            name: "Unassigned", description: nil, type: .feature, project: project
        )

        // Numeric `milestone` must NOT fall through to "no milestone filter" and
        // return every task — it must be rejected.
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["milestone": 42]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("milestone") && errorMessage.contains("string"))
    }

    @Test func queryTasksBooleanMilestoneReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "A", description: nil, type: .bug, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["milestone": false]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("milestone") && errorMessage.contains("string"))
    }

    // MARK: - query_milestones: search

    @Test func queryMilestonesNumericSearchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)
        _ = try await env.milestoneService.createMilestone(name: "v2.0", description: nil, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["search": 42]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("search") && errorMessage.contains("string"))
    }

    @Test func queryMilestonesBooleanSearchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["search": true]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorMessage = try MCPTestHelpers.errorText(response)
        #expect(errorMessage.contains("search") && errorMessage.contains("string"))
    }

    // MARK: - Regression guards: valid string filters still work

    @Test func queryTasksValidStringSearchStillFilters() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "Fix login", description: nil, type: .bug, project: project)
        _ = try await env.taskService.createTask(
            name: "Add dashboard", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["search": "login"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Fix login")
    }

    @Test func queryMilestonesValidStringSearchStillFilters() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(name: "Alpha", description: nil, project: project)
        _ = try await env.milestoneService.createMilestone(name: "Beta", description: nil, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["search": "Alpha"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Alpha")
    }
}

#endif
