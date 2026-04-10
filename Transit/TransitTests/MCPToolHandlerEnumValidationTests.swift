#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPToolHandlerEnumValidationTests {

    // MARK: - query_tasks: invalid status filter

    @Test func queryTasksInvalidStatusArrayReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": ["not-a-status"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("Invalid status"))
        #expect(text.contains("not-a-status"))
    }

    @Test func queryTasksInvalidStatusSingleStringReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": "bogus"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("Invalid status"))
        #expect(text.contains("bogus"))
    }

    @Test func queryTasksMixedValidInvalidStatusReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": ["idea", "not-real"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("not-real"))
    }

    // MARK: - query_tasks: invalid not_status filter

    @Test func queryTasksInvalidNotStatusReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["not_status": ["fake-status"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("Invalid not_status"))
        #expect(text.contains("fake-status"))
    }

    @Test func queryTasksInvalidNotStatusSingleStringReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["not_status": "invalid"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("Invalid not_status"))
    }

    // MARK: - query_tasks: invalid type filter

    @Test func queryTasksInvalidTypeReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["type": "epic"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("Invalid type"))
        #expect(text.contains("epic"))
    }

    // MARK: - query_tasks: valid enum values still work

    @Test func queryTasksValidStatusFilterStillWorks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": ["idea"]]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
    }

    @Test func queryTasksValidTypeFilterStillWorks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Bug", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["type": "bug"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
    }

    // MARK: - query_milestones: invalid status filter

    @Test func queryMilestonesInvalidStatusArrayReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["status": ["not-a-status"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("Invalid status"))
        #expect(text.contains("not-a-status"))
    }

    @Test func queryMilestonesInvalidStatusSingleStringReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["status": "bogus"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("Invalid status"))
        #expect(text.contains("bogus"))
    }

    @Test func queryMilestonesMixedValidInvalidStatusReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["status": ["open", "nope"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("nope"))
    }

    // MARK: - query_milestones: valid status still works

    @Test func queryMilestonesValidStatusFilterStillWorks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "M1", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["status": ["open"]]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
    }
}

#endif
