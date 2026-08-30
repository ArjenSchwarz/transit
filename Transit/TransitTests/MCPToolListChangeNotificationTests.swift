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
/// setting changes must be told that their cached tool list is stale without
/// broadcasting one JSON-RPC message across a session's concurrent streams.
@MainActor @Suite(.serialized)
struct MCPToolListChangeNotificationTests {

    @Test func maintenanceToggleNotifiesEachSessionOnOnlyOneConnectedStream() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = false
        defer { env.mcpSettings.maintenanceToolsEnabled = false }

        let firstSessionID = try await initializeSession(handler: env.handler)
        let secondSessionID = try await initializeSession(handler: env.handler)
        #expect(firstSessionID != secondSessionID)
        let firstStream = try await notificationResponse(
            handler: env.handler,
            sessionID: firstSessionID
        )
        let firstConcurrentStream = try await notificationResponse(
            handler: env.handler,
            sessionID: firstSessionID
        )
        let secondStream = try await notificationResponse(
            handler: env.handler,
            sessionID: secondSessionID
        )

        let firstWriter = RecordingEventWriter()
        let firstConcurrentWriter = RecordingEventWriter()
        let secondWriter = RecordingEventWriter()
        let bodyTasks = [
            bodyTask(response: firstStream.response, writer: firstWriter),
            bodyTask(response: firstConcurrentStream.response, writer: firstConcurrentWriter),
            bodyTask(response: secondStream.response, writer: secondWriter)
        ]

        env.mcpSettings.maintenanceToolsEnabled = true
        try #require(await waitForEventCount(2, writers: [
            firstWriter, firstConcurrentWriter, secondWriter
        ]))

        env.handler.finishToolListChangeSessions()
        for task in bodyTasks {
            try await task.value
        }
        try await firstStream.channel.close()
        try await firstConcurrentStream.channel.close()
        try await secondStream.channel.close()

        let expected = "data: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/tools/list_changed\"}\n\n"
        let firstSessionEvents = firstWriter.events.withLockedValue(\.count)
            + firstConcurrentWriter.events.withLockedValue(\.count)
        #expect(firstSessionEvents == 1)
        #expect(secondWriter.events.withLockedValue { $0 } == [expected])
        #expect(
            firstWriter.events.withLockedValue { $0 } == [expected]
                || firstConcurrentWriter.events.withLockedValue { $0 } == [expected]
        )
        #expect(env.handler.activeToolListChangeStreamCount == 0)
    }

    @Test func assigningExistingMaintenanceValueDoesNotNotify() async throws {
        let env = try MCPTestHelpers.makeEnv()
        env.mcpSettings.maintenanceToolsEnabled = false
        let sessionID = env.handler.createToolListChangeSession()
        let channel = EmbeddedChannel()
        let notifications = try #require(env.handler.toolListChangeNotifications(
            sessionID: sessionID,
            channelClose: channel.closeFuture
        ))

        env.mcpSettings.maintenanceToolsEnabled = false

        let notification = await firstNotification(in: notifications, timeout: .milliseconds(50))
        #expect(notification?.method == nil)
        try await channel.close()
    }

    @Test func closingIdleChannelImmediatelyUnregistersStream() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let sessionID = env.handler.createToolListChangeSession()
        let channel = EmbeddedChannel()
        _ = try #require(env.handler.toolListChangeNotifications(
            sessionID: sessionID,
            channelClose: channel.closeFuture
        ))
        #expect(env.handler.activeToolListChangeStreamCount == 1)

        try await channel.close()

        #expect(await waitForStreamCount(0, handler: env.handler))
    }

    private func initializeSession(handler: MCPToolHandler) async throws -> String {
        let body = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{
        "protocolVersion":"2025-03-26","capabilities":{},
        "clientInfo":{"name":"Transit Tests","version":"1.0"}}}
        """
        let response = try await MCPTestHelpers.respond(
            handler: handler,
            contentType: "application/json",
            accept: "application/json, text/event-stream",
            body: body,
            loggerLabel: "mcp-tool-list-change-initialize"
        )
        #expect(response.status == .ok)
        let result = try #require(response.json as? [String: Any])
        let resultObject = try #require(result["result"] as? [String: Any])
        let capabilities = try #require(resultObject["capabilities"] as? [String: Any])
        let tools = try #require(capabilities["tools"] as? [String: Any])
        #expect(tools["listChanged"] as? Bool == true)
        return try #require(response.sessionID)
    }

    private func bodyTask(
        response: Response,
        writer: RecordingEventWriter
    ) -> Task<Void, any Error> {
        Task {
            try await response.body.write(writer)
        }
    }

    private func firstNotification(
        in notifications: AsyncStream<MCPServerNotification>,
        timeout: Duration
    ) async -> MCPServerNotification? {
        await withTaskGroup(of: MCPServerNotification?.self) { group in
            group.addTask {
                await notifications.first { _ in true }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func notificationResponse(
        handler: MCPToolHandler,
        sessionID: String
    ) async throws -> (response: Response, channel: EmbeddedChannel) {
        let responder = MCPServer.makeRouter(handler: handler).buildResponder()
        var headers = HTTPFields()
        headers[.accept] = "text/event-stream"
        headers[.mcpSessionID] = sessionID
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
        let context = MCPRequestContext(
            source: ApplicationRequestContextSource(
                channel: channel,
                logger: Logger(label: "mcp-tool-list-change-tests")
            )
        )
        return (try await responder.respond(to: request, context: context), channel)
    }

    private func waitForEventCount(
        _ expected: Int,
        writers: [RecordingEventWriter],
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let count = writers.reduce(0) { result, writer in
                result + writer.events.withLockedValue(\.count)
            }
            if count == expected { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func waitForStreamCount(
        _ expected: Int,
        handler: MCPToolHandler,
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if handler.activeToolListChangeStreamCount == expected { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private nonisolated final class RecordingEventWriter: ResponseBodyWriter, @unchecked Sendable {
    let events = NIOLockedValueBox<[String]>([])

    func write(_ buffer: ByteBuffer) async throws {
        events.withLockedValue { $0.append(String(buffer: buffer)) }
    }

    func finish(_: HTTPFields?) async throws {}
}

#endif
