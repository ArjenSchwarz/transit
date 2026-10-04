#if os(macOS)
import Foundation
import HTTPTypes
import SwiftData
import Testing
@testable import Transit

/// One modern request object per POST. Rejected arrays never execute any member;
/// separate ordered objects retain independent correlation and partial commits.
@MainActor @Suite(.serialized)
struct MCPServerBatchRequestTests {
    @Test func rejectedArrayAndSequentialObjectsPreserveFirstCommit() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        try env.context.save()
        let first: [String: Any] = ["name": "First commit", "type": "bug", "projectId": project.id.uuidString,
            "idempotencyKey": "sequential-create"]
        var second = first
        second["name"] = "Must reject conflicting key"
        let firstBody = try MCPModernResultFixture.body(method: "tools/call", id: "first",
            parameters: ["name": "create_task", "arguments": first])
        let secondBody = try MCPModernResultFixture.body(method: "tools/call", id: 2,
            parameters: ["name": "create_task", "arguments": second])
        let rejected = try await respond(env.handler, body: "[\(firstBody),\(secondBody)]",
            method: "tools/call", tool: "create_task")
        try assertArrayRejection(rejected)
        #expect(try env.context.fetchCount(FetchDescriptor<TransitTask>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
        let committed = try await MCPModernResultFixture.respond(env, method: "tools/call", id: "first",
            parameters: ["name": "create_task", "arguments": first])
        let conflict = try await MCPModernResultFixture.respond(env, method: "tools/call", id: 2,
            parameters: ["name": "create_task", "arguments": second])
        let firstRPC = try #require(committed.json as? [String: Any])
        let secondRPC = try #require(conflict.json as? [String: Any])
        #expect(firstRPC["id"] as? String == "first" && secondRPC["id"] as? Int == 2)
        #expect(try MCPTestHelpers.decodeHTTPToolResult(firstRPC)["outcome"] as? String == "committed")
        let failed = try MCPTestHelpers.decodeHTTPToolResult(secondRPC)
        #expect(failed["outcome"] as? String == "rejected")
        #expect((failed["error"] as? [String: Any])?["code"] as? String == "IDEMPOTENCY_KEY_REUSED")
        #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).map(\.name) == ["First commit"])
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 1)
    }

    @Test func allNotificationArrayIsRejectedAsOneInvalidEnvelope() async throws {
        try assertArrayRejection(try await respond(
            body: #"[{"jsonrpc":"2.0","method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"}]"#))
    }

    @Test func notificationMutationArrayHasZeroEffects() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let body = """
        [{"jsonrpc":"2.0","method":"tools/call","params":{"name":"create_task",\
        "arguments":{"idempotencyKey":"batch-notification","name":"Notification task","type":"bug",\
        "projectId":"\(project.id.uuidString)"},"_meta":\(try metadata())}}]
        """
        try assertArrayRejection(try await respond(env.handler, body: body, method: "tools/call", tool: "create_task"))
        #expect(try env.context.fetchCount(FetchDescriptor<TransitTask>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    @Test func emptyArrayReturnsOneInvalidRequestWithoutFabricatedId() async throws {
        try assertArrayRejection(try await respond(body: "[]"))
    }

    @Test func invalidArrayMembersNeverProducePerMemberDispatch() async throws {
        try assertArrayRejection(try await respond(
            body: """
            [17,{"jsonrpc":"2.0","id":2,"method":"tools/list"},
            {"jsonrpc":"2.0","id":false,"method":"tools/list"}]
            """))
    }

    @Test func singleExplicitNullIdReturnsInvalidRequestWithoutId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        try assertNullRejection(try await MCPModernResultFixture.respond(env, method: "tools/list", id: NSNull()))
    }

    @Test(arguments: ["initialize", "ping", "tools/list", "tools/call", "notifications/initialized", "unknown/method"])
    func singleNullIdRejectsBeforeAnyMethodPath(method: String) async throws {
        let env = try MCPTestHelpers.makeEnv()
        try assertNullRejection(try await MCPModernResultFixture.respond(env, method: method, id: NSNull()))
        #expect(try env.context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0)
    }

    @Test func mixedIdArrayRejectsWholeButSeparateReadableIdsCorrelate() async throws {
        try assertArrayRejection(try await respond(body:
            """
            [{"jsonrpc":"2.0","id":null,"method":"tools/list"},
            {"jsonrpc":"2.0","id":7,"method":"tools/list"},
            {"jsonrpc":"2.0","id":"request-1","method":"tools/list"}]
            """))
        let env = try MCPTestHelpers.makeEnv()
        for id in [7, "request-1"] as [Any] {
            let response = try await MCPModernResultFixture.respond(env, method: "tools/list", id: id)
            let object = try #require(response.json as? [String: Any])
            #expect(response.status == .ok && object["result"] != nil)
            let actualID = try #require(object["id"])
            let actualBytes = try JSONSerialization.data(withJSONObject: [actualID])
            let expectedBytes = try JSONSerialization.data(withJSONObject: [id])
            #expect(actualBytes == expectedBytes)
        }
    }

    @Test func initializeArrayRejectsWholeAndFollowingObjectStillWorks() async throws {
        try assertArrayRejection(try await respond(
            body: #"[{"jsonrpc":"2.0","id":1,"method":"initialize"},{"jsonrpc":"2.0","id":2,"method":"ping"}]"#))
        let env = try MCPTestHelpers.makeEnv()
        let response = try await MCPModernResultFixture.respond(env, method: "tools/list", id: 2)
        #expect(response.status == .ok && (response.json as? [String: Any])?["id"] as? Int == 2)
    }

    @Test func singleRequestStillReturnsAResponseObject() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = try await MCPModernResultFixture.respond(env, method: "tools/list", id: 1)
        let object = try #require(response.json as? [String: Any])
        #expect(response.status == .ok && object["id"] as? Int == 1)
        #expect(object["result"] != nil)
    }

    @Test func unknownToolCallOverRouteReturnsInvalidParams() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let response = try await MCPModernResultFixture.respond(env, method: "tools/call", id: 1,
            parameters: ["name": "not_a_real_tool", "arguments": [:] as [String: Any]])
        let object = try #require(response.json as? [String: Any])
        #expect(response.status == .badRequest && object["id"] as? Int == 1)
        #expect((object["error"] as? [String: Any])?["code"] as? Int == JSONRPCErrorCode.invalidParams)
    }

    private func assertArrayRejection(_ response: MCPHTTPTestResponse) throws {
        #expect(response.status == .badRequest && response.contentType == "application/json")
        let object = try #require(response.json as? [String: Any])
        #expect((object["error"] as? [String: Any])?["code"] as? Int == JSONRPCErrorCode.invalidRequest)
        #expect(!object.keys.contains("id") && object["result"] == nil)
    }
    private func assertNullRejection(_ response: MCPHTTPTestResponse) throws { try assertArrayRejection(response) }
    private func metadata() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: MCPModernResultFixture.meta)
        return try #require(String(data: data, encoding: .utf8))
    }
    private func respond(body: String) async throws -> MCPHTTPTestResponse {
        let env = try MCPTestHelpers.makeEnv()
        return try await respond(env.handler, body: body)
    }
    private func respond(_ handler: MCPToolHandler, body: String, method: String = "tools/list",
                         tool: String? = nil) async throws -> MCPHTTPTestResponse {
        var headers = [HTTPField(name: HTTPField.Name("Mcp-Method")!, value: method)]
        if let tool { headers.append(HTTPField(name: HTTPField.Name("Mcp-Name")!, value: tool)) }
        return try await MCPTestHelpers.respond(handler: handler, contentType: "application/json",
            accept: "application/json, text/event-stream", protocolVersion: "2026-07-28", orderedHeaders: headers,
            body: body, loggerLabel: "mcp-batch-tests")
    }
}
#endif
