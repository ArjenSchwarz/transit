#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// MCP's protected envelope contains a full saved record. App Intents retain their
/// existing response shape; compare every intended update field across the surfaces.
@MainActor @Suite(.serialized)
struct UpdateTaskAllFieldsParityTests {

    // MARK: - Helpers

    /// Parses both JSON responses and asserts they are structurally equal.
    /// Bridging through `NSDictionary` gives us deep, order-independent
    /// equality on nested dicts and arrays for free.
    private func assertParity(
        mcp mcpJSON: String,
        intent intentJSON: String,
        task: TransitTask,
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

        #expect(mcpDict["outcome"] as? String == "committed", sourceLocation: sourceLocation)
        #expect(mcpDict["accepted"] as? Bool == true, sourceLocation: sourceLocation)
        let record = try #require(mcpDict["record"] as? [String: Any])
        #expect((record["revision"] as? String)?.hasPrefix("r1:") == true, sourceLocation: sourceLocation)
        let domain = try intentDomainRecord(record, task: task, sourceLocation: sourceLocation)
        let mcpNS = domain as NSDictionary
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
        let response = await env.handler.handle(try MCPTestHelpers.protectedToolCallRequest(
            in: env.context, tool: "update_task", arguments: arguments
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
        let task = try env.taskService.resolveTask(from: arguments)
        let intentInput = try encodeArgsAsJSON(arguments)
        let mcpJSON = try await callMCP(env: env, arguments: arguments)
        let intentJSON = callIntent(env: env, inputJSON: intentInput)
        try assertParity(mcp: mcpJSON, intent: intentJSON, task: task, sourceLocation: sourceLocation)
    }

    // MARK: - Per-Field Parity

    @Test func provisionalTaskWithoutProject_parity() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = TransitTask(name: "Orphan", type: .feature, project: project, displayID: .provisional)
        task.project = nil
        env.context.insert(task)
        try env.context.save()
        try await runParityCase(env: env, arguments: ["taskId": task.id.uuidString, "name": "Renamed"])
    }

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

extension UpdateTaskAllFieldsParityTests {
    /// Verify the full MCP values first, then apply the Intent serializer's omission policy.
    private func intentDomainRecord(
        _ record: [String: Any], task: TransitTask, sourceLocation: SourceLocation
    ) throws -> [String: Any] {
        let domainFields: Set<String> = ["taskId", "name", "type", "priority", "status", "displayId",
                                         "projectId", "projectName", "description", "metadata", "milestone"]
        var domain = record.filter { domainFields.contains($0.key) }
        if let milestone = domain["milestone"] as? [String: Any] {
            domain["milestone"] = milestone.filter { ["milestoneId", "name", "displayId"].contains($0.key) }
        }
        if let description = task.taskDescription {
            #expect(record["description"] as? String == description, sourceLocation: sourceLocation)
            if description.isEmpty { domain.removeValue(forKey: "description") }
        } else {
            #expect(record["description"] is NSNull, sourceLocation: sourceLocation)
            domain.removeValue(forKey: "description")
        }
        let metadata = try #require(record["metadata"] as? [String: String])
        #expect(metadata == task.metadata, sourceLocation: sourceLocation)
        if metadata.isEmpty { domain.removeValue(forKey: "metadata") }
        // Both serializers omit nil display/project IDs, names and milestone assignment.
        // Those fields stay in the comparison, including their presence or absence.
        return domain
    }
}

#endif
