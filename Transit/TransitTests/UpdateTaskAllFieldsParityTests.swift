#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Cross-surface parity tests for the `update_task` MCP tool and
/// `UpdateTaskIntent` App Intent (T-650 AC 8.1).
///
/// Both surfaces share `TaskUpdateValidator` and
/// `IntentHelpers.taskUpdateResponseDict`, so structural equality of the
/// success response is guaranteed by construction. These tests make that
/// contract explicit, so a future divergence (an extra key in one surface, a
/// JSON serialization quirk, etc.) is caught at test time rather than
/// silently changing the wire format for one caller.
///
/// Strategy: each test prepares a single task and a single set of update args,
/// then invokes both surfaces against that same task in the same context. The
/// first call mutates the task; the second call sees the post-mutation state
/// and either:
///   - re-applies the same change (idempotent, response unchanged), or
///   - is a true no-op for identifier-only cases.
/// Either way, both responses are computed from the task's final model state
/// via the shared response builder, so the dictionaries must match exactly.
///
/// Error-response parity is explicitly NOT asserted here — AC 5.2 permits the
/// two surfaces to surface different error messages for the same invalid
/// input. Success-only coverage is what this test exists for.
@MainActor @Suite(.serialized)
struct UpdateTaskAllFieldsParityTests {

    // MARK: - Helpers

    /// Parses both JSON responses and asserts they are structurally equal.
    /// Bridging through `NSDictionary` gives us deep, order-independent
    /// equality on nested dicts and arrays for free.
    private func assertParity(
        mcp mcpJSON: String,
        intent intentJSON: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let mcpData = try #require(mcpJSON.data(using: .utf8))
        let intentData = try #require(intentJSON.data(using: .utf8))
        let mcpDict = try #require(
            try JSONSerialization.jsonObject(with: mcpData) as? [String: Any]
        )
        let intentDict = try #require(
            try JSONSerialization.jsonObject(with: intentData) as? [String: Any]
        )

        // Sanity guard: success-only contract. If either surface returned an
        // error envelope, the test setup is wrong — surface the underlying
        // payload rather than letting the equality check report a confusing
        // diff between two error shapes.
        #expect(
            mcpDict["error"] == nil,
            "MCP returned error envelope: \(mcpDict)",
            sourceLocation: sourceLocation
        )
        #expect(
            intentDict["error"] == nil,
            "Intent returned error envelope: \(intentDict)",
            sourceLocation: sourceLocation
        )

        let mcpNS = mcpDict as NSDictionary
        let intentNS = intentDict as NSDictionary
        #expect(
            mcpNS == intentNS,
            "MCP and Intent responses diverge.\nMCP: \(mcpDict)\nIntent: \(intentDict)",
            sourceLocation: sourceLocation
        )
    }

    /// Extracts the JSON text payload from an MCP `tools/call` response.
    private func mcpResponseText(_ response: JSONRPCResponse?) throws -> String {
        let unwrapped = try #require(response, "Expected a JSON-RPC response but got nil")
        let data = try JSONEncoder().encode(unwrapped)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = try #require(json?["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        return try #require(content.first?["text"] as? String)
    }

    /// Invokes the MCP `update_task` tool with the given arguments and
    /// returns the JSON string payload from the response.
    private func callMCP(
        env: MCPTestEnv,
        arguments: [String: Any]
    ) async throws -> String {
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task", arguments: arguments
        ))
        return try mcpResponseText(response)
    }

    /// Invokes `UpdateTaskIntent.execute` directly with the given JSON input
    /// and returns the JSON string payload.
    private func callIntent(env: MCPTestEnv, inputJSON: String) -> String {
        UpdateTaskIntent.execute(
            input: inputJSON,
            taskService: env.taskService,
            milestoneService: env.milestoneService
        )
    }

    /// Encodes a `[String: Any]` argument dict to a JSON string suitable for
    /// `UpdateTaskIntent.execute`. Sorts keys so the wire string is
    /// deterministic — the input shape is what matters for parity, not
    /// JSON-string byte-identity.
    private func encodeArgsAsJSON(_ args: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: args, options: [.sortedKeys]
        )
        return try #require(String(data: data, encoding: .utf8))
    }

    /// Runs the same update args through both surfaces against the same task
    /// in the same context, then asserts the JSON responses match.
    private func runParityCase(
        env: MCPTestEnv,
        arguments: [String: Any],
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let intentInput = try encodeArgsAsJSON(arguments)
        let mcpJSON = try await callMCP(env: env, arguments: arguments)
        let intentJSON = callIntent(env: env, inputJSON: intentInput)
        try assertParity(mcp: mcpJSON, intent: intentJSON, sourceLocation: sourceLocation)
    }

    // MARK: - Per-Field Parity

    @Test func updateName_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Original", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        try await runParityCase(
            env: env,
            arguments: ["displayId": taskDisplayId, "name": "  renamed  "]
        )
    }

    @Test func updateDescription_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: "old", type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        try await runParityCase(
            env: env,
            arguments: ["displayId": taskDisplayId, "description": "new desc"]
        )
    }

    @Test func clearDescription_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: "current", type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        try await runParityCase(
            env: env,
            arguments: ["displayId": taskDisplayId, "description": ""]
        )
    }

    @Test func updateType_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .bug, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        try await runParityCase(
            env: env,
            arguments: ["displayId": taskDisplayId, "type": "feature"]
        )
    }

    @Test func updatePriority_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        try await runParityCase(
            env: env,
            arguments: ["displayId": taskDisplayId, "priority": "high"]
        )
    }

    @Test func updateMetadata_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        try await runParityCase(
            env: env,
            arguments: ["displayId": taskDisplayId, "metadata": ["k": "v"]]
        )
    }

    @Test func clearMetadata_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project,
            metadata: ["a": "1"]
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        try await runParityCase(
            env: env,
            arguments: ["displayId": taskDisplayId, "metadata": [String: String]()]
        )
    }

    // MARK: - Combined / Atomic

    /// AC 8.1's load-bearing case: a single call exercising every supported
    /// update field (including a milestone assignment) must produce the same
    /// response shape from both surfaces. If this passes, the per-field
    /// cases above are belt-and-braces — but each per-field case still
    /// catches narrower regressions (e.g., a key omission rule that only
    /// affects metadata).
    @Test func combinedAllFields_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Original", description: "old", type: .bug, project: project,
            metadata: ["a": "1"]
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let milestoneDisplayId = try #require(milestone.permanentDisplayId)

        try await runParityCase(
            env: env,
            arguments: [
                "displayId": taskDisplayId,
                "name": "Renamed",
                "description": "new desc",
                "type": "chore",
                "priority": "high",
                "metadata": ["new": "val"],
                "milestoneDisplayId": milestoneDisplayId
            ]
        )
    }

    // MARK: - No-Op Echo

    @Test func noOpEcho_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: "desc", type: .feature, project: project,
            metadata: ["a": "1"]
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        try await runParityCase(
            env: env,
            arguments: ["displayId": taskDisplayId]
        )
    }

    // MARK: - Milestone

    @Test func milestoneAssign_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let milestoneDisplayId = try #require(milestone.permanentDisplayId)

        try await runParityCase(
            env: env,
            arguments: [
                "displayId": taskDisplayId,
                "milestoneDisplayId": milestoneDisplayId
            ]
        )
    }

    @Test func milestoneClear_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)
        #expect(task.milestone != nil)
        let taskDisplayId = try #require(task.permanentDisplayId)

        try await runParityCase(
            env: env,
            arguments: ["displayId": taskDisplayId, "clearMilestone": true]
        )
    }
}

#endif
