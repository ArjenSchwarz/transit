#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1095: `query_tasks` declared `unfinished` as a boolean filter but resolved it
// with `args["unfinished"] as? Bool ?? false`. A present-but-non-boolean value
// (string "true", numeric 1, null) was silently coerced to `false`, returning
// done/abandoned tasks even though the caller attempted to request unfinished-only
// results. The handler must reject malformed `unfinished` values instead.
@MainActor @Suite(.serialized)
struct MCPUnfinishedFlagValidationTests {

    /// Seeds one unfinished (idea) task and one done task, returning the env.
    private func makeEnvWithMixedTasks() async throws -> MCPTestEnv {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Open task", description: nil, type: .feature, project: project
        )
        let doneTask = try await env.taskService.createTask(
            name: "Finished task", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: doneTask, to: .done)
        return env
    }

    @Test func stringUnfinishedIsRejected() async throws {
        let env = try await makeEnvWithMixedTasks()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["unfinished": "true"]
        ))

        // Expected: error rejecting the malformed flag.
        // Previous (buggy) behaviour: silently treated as false, returning all tasks.
        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("unfinished must be a boolean"))
    }

    @Test func numericUnfinishedIsRejected() async throws {
        let env = try await makeEnvWithMixedTasks()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["unfinished": 1]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("unfinished must be a boolean"))
    }

    @Test func nullUnfinishedIsRejected() async throws {
        let env = try await makeEnvWithMixedTasks()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["unfinished": NSNull()]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("unfinished must be a boolean"))
    }

    @Test func validTrueUnfinishedExcludesDoneTasks() async throws {
        let env = try await makeEnvWithMixedTasks()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["unfinished": true]
        ))

        #expect(try MCPTestHelpers.isError(response) == false)
        let results = try MCPTestHelpers.decodeArrayResult(response)
        let names = results.compactMap { $0["name"] as? String }
        #expect(names.contains("Open task"))
        #expect(!names.contains("Finished task"))
    }

    @Test func omittedUnfinishedReturnsAllTasks() async throws {
        let env = try await makeEnvWithMixedTasks()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        #expect(try MCPTestHelpers.isError(response) == false)
        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)
    }
}

#endif
