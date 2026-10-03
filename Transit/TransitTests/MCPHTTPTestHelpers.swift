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

@MainActor
extension MCPTestHelpers {
    static func decodeHTTPToolResult(_ object: [String: Any]) throws -> [String: Any] {
        let result = try #require(object["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        let bytes = try #require(text.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    static func respond(
        handler: MCPToolHandler,
        method: HTTPRequest.Method = .post,
        path: String = "/mcp",
        origin: String? = nil,
        authority: String = "127.0.0.1:3141",
        contentType: String? = nil,
        accept: String? = nil,
        sessionID: String? = nil,
        body: String = "",
        loggerLabel: String
    ) async throws -> MCPHTTPTestResponse {
        let responder = MCPServer.makeRouter(handler: handler).buildResponder()
        var headers = HTTPFields()
        if let origin {
            headers[.origin] = origin
        }
        if let contentType {
            headers[.contentType] = contentType
        }
        if let accept {
            headers[.accept] = accept
        }
        if let sessionID {
            headers[.mcpSessionID] = sessionID
        }
        let request = Request(
            head: HTTPRequest(
                method: method,
                scheme: "http",
                authority: authority,
                path: path,
                headerFields: headers
            ),
            body: RequestBody(buffer: ByteBuffer(string: body))
        )

        let channel = EmbeddedChannel()
        defer { _ = try? channel.finish() }
        let context = MCPRequestContext(
            source: ApplicationRequestContextSource(
                channel: channel,
                logger: Logger(label: loggerLabel)
            )
        )

        let response = try await responder.respond(to: request, context: context)
        let writer = MCPHTTPTestResponseWriter()
        try await response.body.write(writer)
        let data = Data(buffer: writer.collated.withLockedValue { $0 })
        return MCPHTTPTestResponse(
            status: response.status,
            headers: response.headers,
            body: data
        )
    }
}

nonisolated struct MCPHTTPTestResponse {
    let status: HTTPResponse.Status
    let headers: HTTPFields
    let body: Data

    var contentType: String? { headers[.contentType] }
    var allow: String? { headers[.allow] }
    var sessionID: String? { headers[.mcpSessionID] }

    var json: Any? {
        guard !body.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: body)
    }
}

private nonisolated final class MCPHTTPTestResponseWriter: ResponseBodyWriter {
    let collated = NIOLockedValueBox(ByteBuffer())

    func write(_ buffer: ByteBuffer) async throws {
        _ = collated.withLockedValue { $0.writeImmutableBuffer(buffer) }
    }

    func finish(_: HTTPFields?) async throws {}
}
#endif
