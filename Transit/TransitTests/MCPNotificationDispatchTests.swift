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

/// T-1820: a JSON-RPC notification executes its method normally and only
/// suppresses its JSON-RPC response. These cases cover the direct handler and
/// Streamable HTTP transport paths for mutating tools.
@MainActor @Suite(.serialized)
struct MCPNotificationDispatchTests {

    @Test func directToolCallNotificationExecutesMutationButSuppressesResponse() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let request = try JSONDecoder().decode(
            JSONRPCRequest.self,
            from: Data(
                """
                {
                  "jsonrpc":"2.0",
                  "method":"tools/call",
                  "params":{
                    "name":"create_task",
                    "arguments":{
                      "name":"Direct notification task",
                      "type":"bug",
                      "projectId":"\(project.id.uuidString)"
                    }
                  }
                }
                """.utf8
            )
        )

        #expect(request.isNotification)
        #expect(await env.handler.handle(request) == nil)

        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.map(\.name) == ["Direct notification task"])
    }

    @Test func singleToolCallNotificationOverHTTPExecutesMutationWithAcceptedNoBody() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = try await respond(handler: env.handler, body: """
        {
          "jsonrpc":"2.0",
          "method":"tools/call",
          "params":{
            "name":"add_comment",
            "arguments":{
              "displayId":\(displayId),
              "content":"Created over HTTP",
              "authorName":"TestBot"
            }
          }
        }
        """)

        #expect(response.status == .accepted)
        #expect(response.body.isEmpty)
        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.map(\.content) == ["Created over HTTP"])
    }

    @Test func mixedBatchExecutesNotificationBeforeRequestAndSuppressesNotificationFailures() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = try await respond(handler: env.handler, body: """
        [
          {
            "jsonrpc":"2.0",
            "method":"tools/call",
            "params":{
              "name":"update_task_status",
              "arguments":{"displayId":\(displayId),"status":"planning"}
            }
          },
          {
            "jsonrpc":"2.0",
            "id":"after-mutation",
            "method":"tools/call",
            "params":{
              "name":"query_tasks",
              "arguments":{"displayId":\(displayId)}
            }
          },
          {
            "jsonrpc":"2.0",
            "method":"tools/call",
            "params":{"name":"not_a_real_tool","arguments":{}}
          }
        ]
        """)

        #expect(response.status == .ok)
        let objects = try #require(response.json as? [[String: Any]])
        #expect(
            objects.count == 1,
            "Notification success and failure responses must both be suppressed"
        )
        let object = try #require(objects.first)
        #expect(object["id"] as? String == "after-mutation")

        let result = try #require(object["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let returnedTasks = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]]
        )
        #expect(returnedTasks.map { $0["status"] as? String } == ["planning"])
        #expect(task.status == .planning)
    }

    private func respond(
        handler: MCPToolHandler,
        body: String
    ) async throws -> NotificationCapturedResponse {
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
                channel: channel,
                logger: Logger(label: "mcp-notification-dispatch-tests")
            )
        )

        let response = try await responder.respond(to: request, context: context)
        let writer = NotificationCollatedResponseWriter()
        try await response.body.write(writer)
        let data = Data(buffer: writer.collated.withLockedValue { $0 })
        return NotificationCapturedResponse(status: response.status, body: data)
    }
}

private nonisolated struct NotificationCapturedResponse {
    let status: HTTPResponse.Status
    let body: Data

    var json: Any? {
        guard !body.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: body)
    }
}

private nonisolated final class NotificationCollatedResponseWriter: ResponseBodyWriter {
    let collated = NIOLockedValueBox(ByteBuffer())

    func write(_ buffer: ByteBuffer) async throws {
        collated.withLockedValue { $0.writeImmutableBuffer(buffer) }
    }

    func finish(_: HTTPFields?) async throws {}
}

#endif
