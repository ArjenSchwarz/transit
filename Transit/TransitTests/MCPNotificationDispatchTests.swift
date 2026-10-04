#if os(macOS)
import Foundation
import HTTPTypes
import SwiftData
import Testing
@testable import Transit

/// Modern HTTP rejects client notifications before effects; ordered valid
/// request objects retain their own correlation and mutation/read ordering.
@MainActor @Suite(.serialized)
struct MCPNotificationDispatchTests {
    @Test func directNotificationIsRejectedBeforeMutation() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let body = try notification(tool: "create_task", arguments: ["idempotencyKey": "direct-notification",
            "name": "Direct notification task", "type": "bug", "projectId": project.id.uuidString])
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(body.utf8))
        #expect(request.isNotification)
        let response = try #require(await env.handler.handle(request))
        #expect(response.error?.code == JSONRPCErrorCode.invalidRequest)
        #expect(response.id == nil && response.result == nil)
        #expect(try env.context.fetchCount(FetchDescriptor<TransitTask>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    @Test func HTTPNotificationIsRejectedWithoutCommentOrReceipt() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project)
        let response = try await respond(env.handler, body: notification(tool: "add_comment",
            arguments: ["taskId": task.id.uuidString, "idempotencyKey": "http-comment",
                "content": "Created over HTTP", "authorName": "TestBot"]), tool: "add_comment")
        #expect(response.status == .badRequest && response.body.isEmpty)
        #expect(try env.commentService.fetchComments(for: task.id).isEmpty)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    @Test func unknownToolNotificationNeverProducesRPCResponseOrEffects() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = try await respond(env.handler, body: notification(tool: "not_a_real_tool", arguments: [:]),
            tool: "not_a_real_tool")
        #expect(response.status == .badRequest && response.body.isEmpty)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    @Test func rejectedArrayHasNoEffectsAndSequentialObjectsPreserveMutationReadOrder() async throws {
        let env = try MCPModernResultFixture.makeEnvWithReads()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project)
        let arguments: [String: Any] = ["taskId": task.id.uuidString, "status": "planning",
            "idempotencyKey": "ordered-status",
            "expectedRevision": try MCPTestHelpers.readRevision(task, in: env.context)]
        let mutation = try MCPModernResultFixture.body(method: "tools/call", id: "mutation",
            parameters: ["name": "update_task_status", "arguments": arguments])
        let response = try await respond(env.handler,
            body: "[\(try notification(tool: "update_task_status", arguments: arguments)),\(mutation)]",
            tool: "update_task_status")
        #expect(response.status == .badRequest)
        #expect(task.status != .planning)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
        let committed = try await MCPModernResultFixture.respond(env, method: "tools/call", id: "mutation",
            parameters: ["name": "update_task_status", "arguments": arguments])
        #expect((committed.json as? [String: Any])?["id"] as? String == "mutation")
        #expect(task.status == .planning)
        let read = try await MCPModernResultFixture.respond(env, method: "tools/call", id: 17,
            parameters: ["name": "query_tasks", "arguments": ["taskIds": [task.id.uuidString],
                "detailLevel": "full", "includeComments": false, "limit": 100]])
        #expect((read.json as? [String: Any])?["id"] as? Int == 17)
        let payload = try MCPTestHelpers.decodeHTTPToolResult(try #require(read.json as? [String: Any]))
        let results = try #require(payload["results"] as? [[String: Any]])
        let saved = try #require(results.first?["task"] as? [String: Any])
        #expect(saved["status"] as? String == "planning")
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 1)
    }

    @Test func rejectedLifecycleNotificationArrayDoesNotPreventLaterValidRequest() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let rejected = try await respond(env.handler,
            body: #"[{"jsonrpc":"2.0","method":"initialize"},{"jsonrpc":"2.0","id":1,"method":"ping"}]"#,
            tool: nil, method: "initialize")
        #expect(rejected.status == .badRequest)
        #expect(env.handler.activeToolListChangeStreamCount == 0)
        let valid = try await MCPModernResultFixture.respond(env, method: "tools/list", id: "after-initialize")
        let object = try #require(valid.json as? [String: Any])
        #expect(valid.status == .ok && object["id"] as? String == "after-initialize")
        #expect(object["result"] != nil)
    }

    private func notification(tool: String, arguments: [String: Any]) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "tools/call",
            "params": ["name": tool, "arguments": arguments, "_meta": MCPModernResultFixture.meta]])
        return try #require(String(data: bytes, encoding: .utf8))
    }
    private func respond(_ handler: MCPToolHandler, body: String, tool: String?,
                         method: String = "tools/call") async throws -> MCPHTTPTestResponse {
        var headers = [HTTPField(name: HTTPField.Name("Mcp-Method")!, value: method)]
        if let tool { headers.append(HTTPField(name: HTTPField.Name("Mcp-Name")!, value: tool)) }
        return try await MCPTestHelpers.respond(handler: handler, contentType: "application/json",
            accept: "application/json, text/event-stream", protocolVersion: "2026-07-28", orderedHeaders: headers,
            body: body, loggerLabel: "mcp-notification-dispatch-tests")
    }
}
#endif
