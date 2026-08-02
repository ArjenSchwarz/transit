#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import NIOFoundationCompat
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

    private func respond(body: String) async throws -> CapturedResponse {
        let env = try MCPTestHelpers.makeEnv()
        return try await respond(handler: env.handler, body: body)
    }

    private func respond(
        handler: MCPToolHandler,
        body: String
    ) async throws -> CapturedResponse {
        let responder = MCPServer.makeRouter(handler: handler).buildResponder()
        let request = Request(
            head: HTTPRequest(
                method: .post,
                scheme: "http",
                authority: "127.0.0.1:3141",
                path: "/mcp",
                headerFields: [.contentType: "application/json"]
            ),
            body: RequestBody(buffer: ByteBuffer(string: body))
        )

        let channel = EmbeddedChannel()
        defer { _ = try? channel.finish() }
        let context = BasicRequestContext(
            source: ApplicationRequestContextSource(
                channel: channel, logger: Logger(label: "mcp-batch-tests")
            )
        )

        let response = try await responder.respond(to: request, context: context)
        let writer = CollatedResponseWriter()
        try await response.body.write(writer)
        let data = Data(buffer: writer.collated.withLockedValue { $0 })
        return CapturedResponse(
            status: response.status,
            contentType: response.headers[.contentType],
            body: data
        )
    }
}

private nonisolated struct CapturedResponse {
    let status: HTTPResponse.Status
    let contentType: String?
    let body: Data

    var json: Any? {
        guard !body.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: body)
    }
}

private nonisolated final class CollatedResponseWriter: ResponseBodyWriter {
    let collated = NIOLockedValueBox(ByteBuffer())

    func write(_ buffer: ByteBuffer) async throws {
        collated.withLockedValue { $0.writeImmutableBuffer(buffer) }
    }

    func finish(_: HTTPFields?) async throws {}
}

#endif
