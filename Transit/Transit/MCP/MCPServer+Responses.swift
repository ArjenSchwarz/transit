#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOFoundationCompat

extension MCPServer {
    nonisolated static func jsonResponse(
        _ payload: some Encodable & Sendable,
        additionalHeaders: HTTPFields = [:]
    ) -> Response {
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            let fallback = """
            {"jsonrpc":"2.0","id":null,\
            "error":{"code":-32603,"message":"Encoding failed"}}
            """
            data = Data(fallback.utf8)
        }
        var headers = additionalHeaders
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}

#endif
