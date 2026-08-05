#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import NIOFoundationCompat
@testable import Transit

@MainActor
extension MCPTestHelpers {

    static func respond(
        handler: MCPToolHandler,
        method: HTTPRequest.Method = .post,
        path: String = "/mcp",
        origin: String? = nil,
        authority: String = "127.0.0.1:3141",
        contentType: String? = nil,
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
        let context = BasicRequestContext(
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
            contentType: response.headers[.contentType],
            allow: response.headers[.allow],
            body: data
        )
    }
}

nonisolated struct MCPHTTPTestResponse {
    let status: HTTPResponse.Status
    let contentType: String?
    let allow: String?
    let body: Data

    var json: Any? {
        guard !body.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: body)
    }
}

private nonisolated final class MCPHTTPTestResponseWriter: ResponseBodyWriter {
    let collated = NIOLockedValueBox(ByteBuffer())

    func write(_ buffer: ByteBuffer) async throws {
        collated.withLockedValue { $0.writeImmutableBuffer(buffer) }
    }

    func finish(_: HTTPFields?) async throws {}
}
#endif
