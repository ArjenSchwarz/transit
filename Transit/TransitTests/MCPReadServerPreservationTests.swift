#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Actual existing router/lifecycle APIs. No substitute for process-lifetime injection tests.
@MainActor @Suite(.serialized)
struct MCPReadServerPreservationTests {
    @Test(arguments: ["query_tasks", "query_milestones", "get_projects"])
    func stoppedServerRejectsEveryCoveredReadWithoutCaptureIdentity(tool: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        await server.stop()
        let response = try await call(env.handler, tool: tool, args: [:])
        let result = try #require(response["result"] as? [String: Any])
        let meta = try #require((result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
        #expect(meta["category"] as? String == "READ_BUSY")
        #expect(meta["snapshotId"] == nil && meta["asOf"] == nil)
        #expect(result["isError"] as? Bool == true)
    }

    @Test func staleListenerExitDoesNotCloseCurrentAdmission() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let server = MCPServer(toolHandler: env.handler)
        #expect(env.handler.taskQueryAdmissionOpen)
        server.listenerDidExit(generation: -1, failure: "stale failure")
        #expect(env.handler.taskQueryAdmissionOpen)
        #expect(server.startError == nil)
        let response = try await call(env.handler, tool: "get_projects", args: [:])
        #expect(response["error"] == nil)
    }

    @Test func protectedWriteReplayKeepsOriginalProjectionAndReceiptOutsideReadMetadata() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let args: [String: Any] = ["name": "Original", "colorHex": "#112233", "idempotencyKey": "read-preservation"]
        let first = try await call(env.handler, tool: "create_project", args: args)
        let saved = try #require(try env.context.fetch(FetchDescriptor<Project>()).first)
        saved.name = "Later UI name"
        try env.context.save()
        let replay = try await call(env.handler, tool: "create_project", args: args)
        let firstTool = try #require(first["result"] as? [String: Any])
        let replayTool = try #require(replay["result"] as? [String: Any])
        #expect(firstTool["_meta"] == nil && replayTool["_meta"] == nil)
        let firstText = try #require((firstTool["content"] as? [[String: Any]])?.first?["text"] as? String)
        #expect((replayTool["content"] as? [[String: Any]])?.first?["text"] as? String == firstText)
        let logical = try MCPTestHelpers.decodeHTTPToolResult(first)
        #expect(logical["outcome"] as? String == "committed")
        #expect(logical["replayExpiresAt"] is String)
        #expect(try env.context.fetch(FetchDescriptor<MCPWriteReceipt>()).count == 1)
        #expect(try env.context.fetch(FetchDescriptor<Project>()).count == 1)
    }

    @Test func maintenanceScanRemainsOutsideFreshnessAndStoppedReadAdmission() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = true
        let server = MCPServer(toolHandler: env.handler)
        await server.stop()
        let response = try await call(env.handler, tool: "scan_duplicate_display_ids", args: [:])
        let tool = try #require(response["result"] as? [String: Any])
        #expect(tool["_meta"] == nil)
        #expect(tool["isError"] == nil)
        _ = try MCPTestHelpers.decodeHTTPToolResult(response)
    }

    @Test func staleWriteRevisionPreservesInterveningTaskAndCommentState() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = TransitTask(name: "Original", type: .feature, project: project, displayID: .permanent(63))
        env.context.insert(task)
        try env.context.save()
        let revision = try MCPRecordSnapshot.task(task, in: env.context).revision
        task.name = "Intervening edit"
        try env.context.save()
        let args: [String: Any] = ["taskId": task.id.uuidString, "status": "done", "comment": "not committed",
            "authorName": "A", "expectedRevision": revision, "idempotencyKey": "preserve-stale-revision"]
        let response = try await call(env.handler, tool: "update_task_status", args: args)
        let logical = try MCPTestHelpers.decodeHTTPToolResult(response)
        #expect((logical["error"] as? [String: Any])?["code"] as? String == "REVISION_CONFLICT")
        #expect((response["result"] as? [String: Any])?["_meta"] == nil)
        #expect(task.name == "Intervening edit" && task.status == .idea)
        #expect(try env.context.fetch(FetchDescriptor<Transit.Comment>()).isEmpty)
        #expect(try MCPRecordSnapshot.task(task, in: env.context).revision != revision)
    }

    @Test func fallbackStorageKeepsMaintenanceReadAndRejectsMutations() async throws {
        let env = try MCPTestHelpers.makeEnv(persistence: PersistenceAvailability(isFallbackStorageActive: true))
        env.mcpSettings.maintenanceToolsEnabled = true
        let scan = try await call(env.handler, tool: "scan_duplicate_display_ids", args: [:])
        #expect((scan["result"] as? [String: Any])?["isError"] == nil)
        let write = try await call(env.handler, tool: "create_project", args: [
            "name": "Rejected", "colorHex": "#112233", "idempotencyKey": "fallback-preservation"
        ])
        let logical = try MCPTestHelpers.decodeHTTPToolResult(write)
        #expect((logical["error"] as? [String: Any])?["code"] as? String == "PERSISTENCE_UNAVAILABLE")
        let maintenance = try await call(env.handler, tool: "reassign_duplicate_display_ids", args: [:])
        let tool = try #require(maintenance["result"] as? [String: Any])
        #expect(tool["isError"] as? Bool == true && tool["_meta"] == nil)
        #expect(try env.context.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try env.context.fetch(FetchDescriptor<MCPWriteReceipt>()).isEmpty)
    }

    private func call(_ handler: MCPToolHandler, tool: String, args: [String: Any]) async throws -> [String: Any] {
        let envelope: [String: Any] = ["jsonrpc": "2.0", "id": "preservation-id", "method": "tools/call",
                                      "params": ["name": tool, "arguments": args]]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        let response = try await MCPTestHelpers.respond(handler: handler,
            contentType: "application/json", accept: "application/json", protocolVersion: "2026-07-28",
            body: try #require(String(data: data, encoding: .utf8)), loggerLabel: "read-server-preservation")
        let object = try #require(response.json as? [String: Any])
        #expect(object["id"] as? String == "preservation-id")
        #expect(object["jsonrpc"] as? String == "2.0")
        return object
    }
}
#endif
