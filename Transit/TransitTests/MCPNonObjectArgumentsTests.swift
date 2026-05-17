#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1247: When a JSON-RPC `tools/call` request supplies a present but non-object
// `arguments` value (string, array, number, boolean, null), the handler must
// reject the request with a JSON-RPC `invalidParams` error rather than silently
// treating the value as an empty object `{}`.
//
// Before the fix, `let arguments = dict["arguments"] as? [String: Any] ?? [:]`
// silently coerced non-object shapes to `{}`. For `query_tasks` this caused
// unfiltered data exposure (returned all tasks); for mutation tools it
// returned misleading "missing required field" errors instead of reporting
// the malformed argument shape.
//
// Omitted `arguments` is still allowed and treated as `{}` for tools whose
// inputs are all optional.
@MainActor @Suite(.serialized)
struct MCPNonObjectArgumentsTests {

    // MARK: - JSON-RPC error path

    @Test func toolCallWithStringArgumentsReturnsInvalidParams() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let request = MCPTestHelpers.request(
            method: "tools/call",
            params: ["name": "query_tasks", "arguments": "not an object"]
        )
        let response = try #require(await env.handler.handle(request))

        let error = try jsonRPCError(response)
        #expect(error["code"] as? Int == -32602)
        let message = try #require(error["message"] as? String)
        #expect(message.localizedCaseInsensitiveContains("arguments"))
    }

    @Test func toolCallWithArrayArgumentsReturnsInvalidParams() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let request = MCPTestHelpers.request(
            method: "tools/call",
            params: ["name": "query_tasks", "arguments": ["a", "b"]]
        )
        let response = try #require(await env.handler.handle(request))

        let error = try jsonRPCError(response)
        #expect(error["code"] as? Int == -32602)
    }

    @Test func toolCallWithNumericArgumentsReturnsInvalidParams() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let request = MCPTestHelpers.request(
            method: "tools/call",
            params: ["name": "query_tasks", "arguments": 42]
        )
        let response = try #require(await env.handler.handle(request))

        let error = try jsonRPCError(response)
        #expect(error["code"] as? Int == -32602)
    }

    @Test func toolCallWithBooleanArgumentsReturnsInvalidParams() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let request = MCPTestHelpers.request(
            method: "tools/call",
            params: ["name": "query_tasks", "arguments": true]
        )
        let response = try #require(await env.handler.handle(request))

        let error = try jsonRPCError(response)
        #expect(error["code"] as? Int == -32602)
    }

    @Test func toolCallWithNullArgumentsReturnsInvalidParams() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let request = MCPTestHelpers.request(
            method: "tools/call",
            params: ["name": "query_tasks", "arguments": NSNull()]
        )
        let response = try #require(await env.handler.handle(request))

        let error = try jsonRPCError(response)
        #expect(error["code"] as? Int == -32602)
    }

    // MARK: - Mutation tools (should also be rejected at the JSON-RPC level)

    @Test func mutationToolWithStringArgumentsReturnsInvalidParams() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let request = MCPTestHelpers.request(
            method: "tools/call",
            params: ["name": "create_task", "arguments": "not an object"]
        )
        let response = try #require(await env.handler.handle(request))

        let error = try jsonRPCError(response)
        #expect(error["code"] as? Int == -32602)
    }

    // MARK: - Data exposure regression

    @Test func queryTasksWithNonObjectArgumentsDoesNotReturnAllTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task A", description: nil, type: .feature, project: project, metadata: nil
        )
        _ = try await env.taskService.createTask(
            name: "Task B", description: nil, type: .feature, project: project, metadata: nil
        )

        let request = MCPTestHelpers.request(
            method: "tools/call",
            params: ["name": "query_tasks", "arguments": "not an object"]
        )
        let response = try #require(await env.handler.handle(request))

        // Must be a JSON-RPC error, not a successful tool result.
        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["error"] != nil, "Expected JSON-RPC error, not a successful tool response")
        #expect(json["result"] == nil, "Tool must not execute with malformed arguments shape")
    }

    // MARK: - Omitted arguments still allowed

    @Test func toolCallWithOmittedArgumentsStillSucceedsForAllOptionalTool() async throws {
        let env = try MCPTestHelpers.makeEnv()

        // get_projects has no required arguments; omitting `arguments` entirely
        // must continue to work.
        let request = MCPTestHelpers.request(
            method: "tools/call",
            params: ["name": "get_projects"]
        )
        let response = try #require(await env.handler.handle(request))

        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["error"] == nil)
        #expect(json["result"] != nil)
    }

    @Test func toolCallWithEmptyObjectArgumentsStillSucceedsForAllOptionalTool() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = try #require(await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "get_projects",
            arguments: [:]
        )))

        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["error"] == nil)
        #expect(json["result"] != nil)
    }

    // MARK: - Helpers

    private func jsonRPCError(_ response: JSONRPCResponse) throws -> [String: Any] {
        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["error"] as? [String: Any])
    }
}

#endif
