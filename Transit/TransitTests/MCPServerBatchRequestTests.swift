#if os(macOS)
import Foundation
import HTTPTypes
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1834: the MCP Streamable HTTP endpoint advertises
/// protocol 2025-03-26, so POST bodies may be JSON-RPC request batches.
///
/// Before the fix, `MCPServer.decodeIncomingRequest` decoded only one
/// `JSONRPCRequest`. Every array therefore became a single -32600 response,
/// including valid batches and all-notification batches that require HTTP 202.
@MainActor @Suite(.serialized)
struct MCPServerBatchRequestTests {

    @Test func mixedRequestAndNotificationBatchReturnsOnlyRequestResponses() async throws {
        let response = try await respond(body: """
        [
          {"jsonrpc":"2.0","id":1,"method":"ping"},
          {"jsonrpc":"2.0","method":"ping"},
          {"jsonrpc":"2.0","id":"missing","method":"unknown/method"}
        ]
        """)

        #expect(response.status == .ok)
        #expect(response.contentType == "application/json")
        let objects = try #require(response.json as? [[String: Any]])
        #expect(objects.count == 2)
        #expect(objects.contains { $0["id"] as? Int == 1 && $0["result"] != nil })
        #expect(objects.contains { object in
            object["id"] as? String == "missing"
                && (object["error"] as? [String: Any])?["code"] as? Int
                    == JSONRPCErrorCode.methodNotFound
        })
    }

    @Test func allNotificationBatchReturnsAcceptedWithNoBody() async throws {
        let response = try await respond(body: """
        [
          {"jsonrpc":"2.0","method":"ping"},
          {"jsonrpc":"2.0","method":"notifications/initialized"}
        ]
        """)

        #expect(response.status == .accepted)
        #expect(response.body.isEmpty)
    }

    @Test func toolCallNotificationIsDispatchedButGetsNoResponse() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let response = try await respond(handler: env.handler, body: """
        [{
          "jsonrpc":"2.0",
          "method":"tools/call",
          "params":{
            "name":"create_task",
            "arguments":{
              "name":"Notification task",
              "type":"bug",
              "projectId":"\(project.id.uuidString)"
            }
          }
        }]
        """)

        #expect(response.status == .accepted)
        #expect(response.body.isEmpty)
        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.map(\.name) == ["Notification task"])
    }

    @Test func emptyBatchReturnsSingleInvalidRequestObject() async throws {
        let response = try await respond(body: "[]")

        #expect(response.status == .ok)
        let object = try #require(response.json as? [String: Any])
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? Int == JSONRPCErrorCode.invalidRequest)
        #expect(object["id"] is NSNull)
    }

    @Test func invalidBatchMembersEachProduceAnErrorResponse() async throws {
        let response = try await respond(body: """
        [
          17,
          {"jsonrpc":"2.0","id":2,"method":"ping"},
          {"jsonrpc":"2.0","id":false,"method":"ping"}
        ]
        """)

        #expect(response.status == .ok)
        let objects = try #require(response.json as? [[String: Any]])
        #expect(objects.count == 3)
        #expect(objects.filter { object in
            (object["error"] as? [String: Any])?["code"] as? Int
                == JSONRPCErrorCode.invalidRequest
        }.count == 2)
        #expect(objects.contains { $0["id"] as? Int == 2 && $0["result"] != nil })
    }

    @Test func singleExplicitNullIdReturnsInvalidRequestWithNullId() async throws {
        let response = try await respond(
            body: #"{"jsonrpc":"2.0","id":null,"method":"ping"}"#
        )

        #expect(response.status == .ok)
        let object = try #require(response.json as? [String: Any])
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? Int == JSONRPCErrorCode.invalidRequest)
        #expect(object["id"] is NSNull)
        #expect(object["result"] == nil)
    }

    @Test(arguments: [
        "initialize", "ping", "tools/list", "tools/call",
        "notifications/initialized", "unknown/method"
    ])
    func singleExplicitNullIdIsReturnedForEveryMethodPath(method: String) async throws {
        let response = try await respond(
            body: #"{"jsonrpc":"2.0","id":null,"method":"\#(method)"}"#
        )

        #expect(response.status == .ok)
        let object = try #require(response.json as? [String: Any])
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? Int == JSONRPCErrorCode.invalidRequest)
        #expect(object["id"] is NSNull)
        #expect(object["result"] == nil)
    }

    @Test func batchExplicitNullIdIsInvalidWhileStringAndIntegerIdsRemainValid() async throws {
        let response = try await respond(body: """
        [
          {"jsonrpc":"2.0","id":null,"method":"ping"},
          {"jsonrpc":"2.0","id":7,"method":"ping"},
          {"jsonrpc":"2.0","id":"request-1","method":"ping"},
          {"jsonrpc":"2.0","method":"ping"}
        ]
        """)

        #expect(response.status == .ok)
        let objects = try #require(response.json as? [[String: Any]])
        #expect(objects.count == 3, "The omitted-id notification must have no response")

        let nullResponse = try #require(objects.first { $0["id"] is NSNull })
        let nullError = try #require(nullResponse["error"] as? [String: Any])
        #expect(nullError["code"] as? Int == JSONRPCErrorCode.invalidRequest)
        #expect(nullResponse["result"] == nil)
        #expect(objects.contains { $0["id"] as? Int == 7 && $0["result"] != nil })
        #expect(objects.contains { $0["id"] as? String == "request-1" && $0["result"] != nil })
    }

    @Test func initializeInsideBatchIsRejectedWithoutRejectingOtherRequests() async throws {
        let response = try await respond(body: """
        [
          {"jsonrpc":"2.0","id":1,"method":"initialize"},
          {"jsonrpc":"2.0","id":2,"method":"ping"}
        ]
        """)

        #expect(response.status == .ok)
        let objects = try #require(response.json as? [[String: Any]])
        #expect(objects.count == 2)
        let initializeResponse = try #require(objects.first { $0["id"] as? Int == 1 })
        let error = try #require(initializeResponse["error"] as? [String: Any])
        #expect(error["code"] as? Int == JSONRPCErrorCode.invalidRequest)
        #expect(objects.contains { $0["id"] as? Int == 2 && $0["result"] != nil })
    }

    @Test func singleRequestStillReturnsAResponseObject() async throws {
        let response = try await respond(
            body: #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        )

        #expect(response.status == .ok)
        let object = try #require(response.json as? [String: Any])
        #expect(object["id"] as? Int == 1)
        #expect(object["result"] != nil)
    }

    @Test func unknownToolCallOverRouteReturnsInvalidParams() async throws {
        let response = try await respond(
            body: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"not_a_real_tool","arguments":{}}}"#
        )

        #expect(response.status == .ok)
        let object = try #require(response.json as? [String: Any])
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["code"] as? Int == JSONRPCErrorCode.invalidParams)
        #expect(error["message"] as? String == "Unknown tool: not_a_real_tool")
    }

    // MARK: - Helpers

    private func respond(body: String) async throws -> MCPHTTPTestResponse {
        let env = try MCPTestHelpers.makeEnv()
        return try await respond(handler: env.handler, body: body)
    }

    private func respond(
        handler: MCPToolHandler,
        body: String
    ) async throws -> MCPHTTPTestResponse {
        try await MCPTestHelpers.respond(
            handler: handler,
            contentType: "application/json",
            body: body,
            loggerLabel: "mcp-batch-tests"
        )
    }
}

#endif
