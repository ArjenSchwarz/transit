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

/// Request-scoped asynchronous transport; owns and drains its channel, writer and loop.
@MainActor final class MCPSubscriptionFixture {
    let response: Response
    let writer = Writer()
    private let loop: NIOAsyncTestingEventLoop
    private let handler: MCPToolHandler
    private let channel: NIOAsyncTestingChannel
    private var bodyTask: Task<Void, any Error>?
    private var closed = false

    private init(response: Response, loop: NIOAsyncTestingEventLoop, channel: NIOAsyncTestingChannel,
                 handler: MCPToolHandler) {
        self.response = response
        self.loop = loop
        self.channel = channel
        self.handler = handler
    }

    static func open(handler: MCPToolHandler, id: Any = 7,
                     filters: [String: Any] = ["toolsListChanged": true]) async throws -> MCPSubscriptionFixture {
        let loop = NIOAsyncTestingEventLoop()
        var ownedChannel: NIOAsyncTestingChannel?
        do {
            let channel = try await NIOAsyncTestingChannel(loop: loop) { _ in }
            ownedChannel = channel
            let body = try MCPModernResultFixture.body(method: "subscriptions/listen", id: id,
                parameters: ["notifications": filters])
            let headers: HTTPFields = [
                .contentType: "application/json", .accept: "text/event-stream",
                HTTPField.Name("MCP-Protocol-Version")!: "2026-07-28",
                HTTPField.Name("Mcp-Method")!: "subscriptions/listen"
            ]
            let request = Request(head: HTTPRequest(method: .post, scheme: "http", authority: "127.0.0.1:3141",
                path: "/mcp", headerFields: headers), body: RequestBody(buffer: ByteBuffer(string: body)))
            let context = MCPRequestContext(source: ApplicationRequestContextSource(channel: channel,
                logger: Logger(label: "t2383-subscription-fixture")))
            let response = try await MCPServer.makeRouter(handler: handler).buildResponder()
                .respond(to: request, context: context)
            return MCPSubscriptionFixture(response: response, loop: loop, channel: channel, handler: handler)
        } catch {
            if let channel = ownedChannel {
                do { _ = try await channel.finish(acceptAlreadyClosed: true) } catch {
                    Issue.record("Subscription setup channel cleanup failed: \(error)")
                }
            }
            await loop.shutdownGracefully()
            throw error
        }
    }

    /// Delaying body consumption proves registration/ack staging without relying on timing.
    func startBody() {
        precondition(bodyTask == nil)
        let response = response, writer = writer
        bodyTask = Task {
            defer { writer.bodyCompleted.withLockedValue { $0 = true } }
            try await response.body.write(writer)
        }
    }

    func cancelBodyOnly() { bodyTask?.cancel() }

    func close(cancelBody: Bool = false) async {
        guard !closed else { return }
        closed = true
        if cancelBody { bodyTask?.cancel() }
        do {
            let leftovers = try await channel.finish(acceptAlreadyClosed: true)
            #expect(leftovers.isClean)
        } catch { Issue.record("Owned subscription channel cleanup failed: \(error)") }
        if bodyTask != nil {
            let completed = await Self.wait { writer.bodyCompleted.withLockedValue { $0 } }
            #expect(completed, "Channel close/cancellation must finish the body without cleanup cancellation")
            if !completed {
                handler.finishToolListChangeSessions() // Cleanup only after the disconnect oracle has failed.
                bodyTask?.cancel()
                let drained = await Self.wait { writer.bodyCompleted.withLockedValue { $0 } }
                #expect(drained, "Cleanup cancellation did not drain owned subscription body")
            }
        }
        if let bodyTask, writer.bodyCompleted.withLockedValue({ $0 }) {
            do { try await bodyTask.value } catch is CancellationError { } catch {
                if !(error is SubscriptionWriterFailure) { Issue.record("Subscription body failed: \(error)") }
            }
        }
        await loop.shutdownGracefully()
    }

    func messages() throws -> [[String: Any]] {
        let text = writer.bytes.withLockedValue { String(buffer: $0) }
        var result: [[String: Any]] = []
        for frame in text.components(separatedBy: "\n\n") where !frame.isEmpty {
            #expect(!frame.split(separator: "\n").contains { $0.hasPrefix("id:") },
                "SSE has no event ID/resume token")
            if frame.hasPrefix(":") { continue }
            let data = try #require(frame.split(separator: "\n").first { $0.hasPrefix("data:") })
            let json = data.dropFirst(5).trimmingCharacters(in: .whitespaces)
            result.append(try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]))
        }
        return result
    }

    static func wait(_ predicate: @MainActor () throws -> Bool) async rethrows -> Bool {
        let end = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < end {
            if try predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return try predicate()
    }

    static func assertID(_ message: [String: Any], expected: Any) throws {
        let params = try #require(message["params"] as? [String: Any])
        let meta = try #require(params["_meta"] as? [String: Any])
        let actual = try #require(meta["io.modelcontextprotocol/subscriptionId"])
        #expect(try JSONSerialization.data(withJSONObject: [actual])
            == JSONSerialization.data(withJSONObject: [expected]))
    }

    nonisolated final class Writer: ResponseBodyWriter, Sendable {
        let bytes = NIOLockedValueBox(ByteBuffer())
        let failWrites = NIOLockedValueBox(false)
        let finished = NIOLockedValueBox(false)
        let bodyCompleted = NIOLockedValueBox(false)
        func write(_ buffer: ByteBuffer) async throws {
            if failWrites.withLockedValue({ $0 }) { throw SubscriptionWriterFailure.injected }
            _ = bytes.withLockedValue { $0.writeImmutableBuffer(buffer) }
        }
        func finish(_: HTTPFields?) async throws { finished.withLockedValue { $0 = true } }
    }
}
private nonisolated enum SubscriptionWriterFailure: Error { case injected }
#endif
