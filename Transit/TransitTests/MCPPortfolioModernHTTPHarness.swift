#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import NIOFoundationCompat
import Testing
@testable import Transit

/// Test transport only: the delivered validator/provider remain the protocol/result owners.
nonisolated enum MCPPortfolioModernHTTPHarness {
    struct Response: Sendable {
        let status: HTTPResponse.Status
        let body: Data
        let elapsed: Duration
        var json: Any? { try? JSONSerialization.jsonObject(with: body) }
    }

    static func request(tool: String? = nil, arguments: [String: Any] = [:],
                        method: String = "tools/call", id: Int = 2382) throws -> Data {
        var params: [String: Any] = ["_meta": [
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientCapabilities": [:] as [String: Any]]]
        if let tool { params["name"] = tool; params["arguments"] = arguments }
        return try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id,
                                                           "method": method, "params": params])
    }

    @concurrent static func post(responder: RouterResponder<MCPRequestContext>, body: Data,
                                 tool: String? = nil, method: String = "tools/call",
                                 version: String = "2026-07-28") async throws -> Response {
        let loop = NIOAsyncTestingEventLoop()
        var ownedChannel: NIOAsyncTestingChannel?
        do {
            let channel = try await NIOAsyncTestingChannel(loop: loop) { _ in }
            ownedChannel = channel
            var headers: HTTPFields = [.contentType: "application/json", .accept: "application/json"]
            headers[HTTPField.Name("MCP-Protocol-Version")!] = version
            headers[HTTPField.Name("Mcp-Method")!] = method
            if let tool { headers[HTTPField.Name("Mcp-Name")!] = tool }
            let context = MCPRequestContext(source: ApplicationRequestContextSource(
                channel: channel, logger: Logger(label: "portfolio-modern-router")))
            let request = Request(head: HTTPRequest(method: .post, scheme: "http", authority: "127.0.0.1:3141",
                path: "/mcp", headerFields: headers), body: RequestBody(buffer: ByteBuffer(data: body)))
            let start = ContinuousClock.now
            let response = try await responder.respond(to: request, context: context)
            let writer = Writer()
            try await response.body.write(writer)
            let elapsed = start.duration(to: .now)
            let result = Response(status: response.status,
                body: Data(buffer: writer.bytes.withLockedValue { $0 }), elapsed: elapsed)
            let leftovers = try await channel.finish(acceptAlreadyClosed: true)
            #expect(leftovers.isClean)
            await loop.shutdownGracefully()
            return result
        } catch {
            if let channel = ownedChannel {
                do {
                    let leftovers = try await channel.finish(acceptAlreadyClosed: true)
                    #expect(leftovers.isClean)
                } catch { Issue.record("Modern test channel cleanup failed: \(error)") }
            }
            await loop.shutdownGracefully()
            throw error
        }
    }

    private final class Writer: ResponseBodyWriter, Sendable {
        let bytes = NIOLockedValueBox(ByteBuffer())
        func write(_ buffer: ByteBuffer) async throws { _ = bytes.withLockedValue { $0.writeImmutableBuffer(buffer) } }
        func finish(_: HTTPFields?) async throws {}
    }
}
#endif
