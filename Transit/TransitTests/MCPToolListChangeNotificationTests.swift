#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import Testing
@testable import Transit

/// Regression coverage for T-2169: clients initialized before the maintenance
/// setting changes must be told that their cached tool list is stale.
@MainActor @Suite(.serialized)
struct MCPToolListChangeNotificationTests {

    @Test func maintenanceToggleAfterInitializeNotifiesConnectedClient() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = false
        defer { env.mcpSettings.maintenanceToolsEnabled = false }

        let initializeResponse = try #require(await env.handler.handle(MCPTestHelpers.request(
            method: "initialize",
            params: [
                "protocolVersion": "2025-03-26",
                "capabilities": [:] as [String: Any],
                "clientInfo": ["name": "Transit Tests", "version": "1.0"]
            ]
        )))
        let initializeJSON = try jsonObject(initializeResponse)
        let result = try #require(initializeJSON["result"] as? [String: Any])
        let capabilities = try #require(result["capabilities"] as? [String: Any])
        let tools = try #require(capabilities["tools"] as? [String: Any])
        #expect(tools["listChanged"] as? Bool == true)

        let response = try await notificationResponse(handler: env.handler)
        #expect(response.status == .ok)
        #expect(response.headers[.contentType] == "text/event-stream")

        let writer = FirstEventWriter()
        let bodyTask = Task {
            do {
                try await response.body.write(writer)
            } catch is FirstEventReceived {
                // The test writer deliberately ends an otherwise long-lived SSE stream.
            }
        }

        env.mcpSettings.maintenanceToolsEnabled = true
        try await bodyTask.value

        let event = writer.event.withLockedValue { $0 }
        #expect(event == "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}\n\n")
    }

    private func notificationResponse(handler: MCPToolHandler) async throws -> Response {
        let responder = MCPServer.makeRouter(handler: handler).buildResponder()
        var headers = HTTPFields()
        headers[.accept] = "text/event-stream"
        let request = Request(
            head: HTTPRequest(
                method: .get,
                scheme: "http",
                authority: "127.0.0.1:3141",
                path: "/mcp",
                headerFields: headers
            ),
            body: RequestBody(buffer: ByteBuffer())
        )
        let channel = EmbeddedChannel()
        let context = BasicRequestContext(
            source: ApplicationRequestContextSource(
                channel: channel,
                logger: Logger(label: "mcp-tool-list-change-tests")
            )
        )
        return try await responder.respond(to: request, context: context)
    }

    private func jsonObject(_ response: JSONRPCResponse) throws -> [String: Any] {
        let data = try JSONEncoder().encode(response)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private nonisolated struct FirstEventReceived: Error {}

private nonisolated final class FirstEventWriter: ResponseBodyWriter, @unchecked Sendable {
    let event = NIOLockedValueBox<String?>(nil)

    func write(_ buffer: ByteBuffer) async throws {
        event.withLockedValue { $0 = String(buffer: buffer) }
        throw FirstEventReceived()
    }

    func finish(_: HTTPFields?) async throws {}
}

#endif
