#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Tests for MCPToolHandler maintenance-tool gating and dispatch.
/// Covers AC 5.1, 5.2, 5.3, 5.4, 5.5, 5.6 from the duplicate-displayid-cleanup spec.
@MainActor @Suite(.serialized)
struct MCPMaintenanceHandlerTests {

    // MARK: - tools/list gating

    @Test func toolsListWithMaintenanceOffExcludesBothMaintenanceTools() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = false

        let names = try await fetchToolNames(env: env)

        #expect(!names.contains("scan_duplicate_display_ids"))
        #expect(!names.contains("reassign_duplicate_display_ids"))
        // Core tools still present.
        #expect(names.contains("create_task"))
        #expect(names.count == 10)
    }

    @Test func toolsListWithMaintenanceOnIncludesBothMaintenanceTools() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = true
        defer { env.mcpSettings.maintenanceToolsEnabled = false }

        let names = try await fetchToolNames(env: env)

        #expect(names.contains("scan_duplicate_display_ids"))
        #expect(names.contains("reassign_duplicate_display_ids"))
        #expect(names.count == 12)
    }

    @Test func toggleFlipReflectsImmediatelyInToolsList() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = false
        defer { env.mcpSettings.maintenanceToolsEnabled = false }

        let beforeNames = try await fetchToolNames(env: env)
        #expect(!beforeNames.contains("scan_duplicate_display_ids"))

        env.mcpSettings.maintenanceToolsEnabled = true

        let afterNames = try await fetchToolNames(env: env)
        #expect(afterNames.contains("scan_duplicate_display_ids"))
        #expect(afterNames.contains("reassign_duplicate_display_ids"))
    }

    // MARK: - tools/call gating

    @Test func scanCallWhenDisabledReturnsMethodNotFound() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = false

        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "scan_duplicate_display_ids", arguments: [:])
        )

        let error = try requireError(response)
        #expect(error["code"] as? Int == JSONRPCErrorCode.methodNotFound)
        #expect(
            error["message"] as? String
                == "Tool 'scan_duplicate_display_ids' is disabled. Enable maintenance tools in Transit Settings."
        )
    }

    @Test func reassignCallWhenDisabledReturnsMethodNotFound() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = false

        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "reassign_duplicate_display_ids", arguments: [:])
        )

        let error = try requireError(response)
        #expect(error["code"] as? Int == JSONRPCErrorCode.methodNotFound)
        #expect(
            error["message"] as? String
                == "Tool 'reassign_duplicate_display_ids' is disabled. Enable maintenance tools in Transit Settings."
        )
    }

    // MARK: - Scan dispatch

    @Test func scanCallWhenEnabledReturnsDuplicateReportJSON() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = true
        defer { env.mcpSettings.maintenanceToolsEnabled = false }

        let project = MCPTestHelpers.makeProject(in: env.context)
        let task1 = makeTask(name: "First", displayId: 5, project: project, in: env.context)
        let task2 = makeTask(name: "Second", displayId: 5, project: project, in: env.context)
        try env.context.save()
        // Touch the locals so the compiler doesn't drop them before the fetch.
        _ = (task1, task2)

        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "scan_duplicate_display_ids", arguments: [:])
        )

        let result = try MCPTestHelpers.decodeResult(response)
        let tasks = try #require(result["tasks"] as? [[String: Any]])
        let milestones = try #require(result["milestones"] as? [[String: Any]])
        #expect(tasks.count == 1)
        #expect(milestones.count == 0)
        #expect(tasks.first?["displayId"] as? Int == 5)

        // isError is absent (success) per MCPToolResult.isError == nil convention.
        #expect(try !MCPTestHelpers.isError(response))
    }

    @Test func scanCallWhenEnabledOnEmptyDataReturnsEmptyGroups() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = true
        defer { env.mcpSettings.maintenanceToolsEnabled = false }

        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "scan_duplicate_display_ids", arguments: [:])
        )

        let result = try MCPTestHelpers.decodeResult(response)
        #expect((result["tasks"] as? [[String: Any]])?.isEmpty == true)
        #expect((result["milestones"] as? [[String: Any]])?.isEmpty == true)
    }

    // MARK: - Reassign dispatch

    @Test func reassignCallWhenEnabledReturnsReassignmentResultJSON() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = true
        defer { env.mcpSettings.maintenanceToolsEnabled = false }

        let project = MCPTestHelpers.makeProject(in: env.context)
        let task1 = makeTask(name: "Winner", displayId: 7, project: project, in: env.context)
        let task2 = makeTask(name: "Loser", displayId: 7, project: project, in: env.context)
        try env.context.save()
        _ = (task1, task2)

        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "reassign_duplicate_display_ids", arguments: [:])
        )

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["status"] as? String == "ok")
        let groups = try #require(result["groups"] as? [[String: Any]])
        #expect(groups.count == 1)
        // counterAdvance must always be present in the envelope (nullable per design).
        #expect(result["counterAdvance"] != nil)
    }

    @Test func reassignCallWhenEnabledOnEmptyDataReturnsOkWithEmptyGroups() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = true
        defer { env.mcpSettings.maintenanceToolsEnabled = false }

        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "reassign_duplicate_display_ids", arguments: [:])
        )

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["status"] as? String == "ok")
        #expect((result["groups"] as? [[String: Any]])?.isEmpty == true)
    }

    // MARK: - Helpers

    private func fetchToolNames(env: MCPTestEnv) async throws -> [String] {
        let response = try #require(await env.handler.handle(MCPTestHelpers.request(method: "tools/list")))
        let data = try JSONEncoder().encode(response)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(json["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        return tools.compactMap { $0["name"] as? String }
    }

    private func requireError(_ response: JSONRPCResponse?) throws -> [String: Any] {
        let unwrapped = try #require(response, "Expected a JSON-RPC response but got nil")
        let data = try JSONEncoder().encode(unwrapped)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["error"] as? [String: Any], "Expected an error response")
    }

    private func makeTask(
        name: String, displayId: Int, project: Project, in context: ModelContext
    ) -> TransitTask {
        let task = TransitTask(
            name: name,
            type: .feature,
            project: project,
            displayID: .permanent(displayId)
        )
        context.insert(task)
        return task
    }
}

#endif
