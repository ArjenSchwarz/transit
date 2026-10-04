#if os(macOS)
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOFoundationCompat

extension MCPServer {
    nonisolated static func encodedResponse(_ bytes: Data) -> Response {
        Response(status: .ok, headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: bytes)))
    }

    nonisolated static func modernRejection(_ rejection: MCPModernRejection) -> Response {
        let status = HTTPResponse.Status(code: rejection.httpStatus)
        guard rejection.rpcCode != nil else { return Response(status: status) }
        guard let bytes = try? MCPModernWire.error(rejection) else {
            return Response(status: .internalServerError)
        }
        return Response(status: status, headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: bytes)))
    }

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
