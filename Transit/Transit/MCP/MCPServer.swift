#if os(macOS)
import Foundation
import Hummingbird
import NIOCore
import NIOFoundationCompat

@MainActor @Observable
final class MCPServer {

    private let toolHandler: MCPToolHandler
    private var serverTask: Task<Void, Never>?
    private var generation = 0

    private(set) var isRunning = false

    init(toolHandler: MCPToolHandler) {
        self.toolHandler = toolHandler
    }

    func start(port: Int) {
        guard !isRunning else { return }
        generation += 1
        let currentGeneration = generation
        isRunning = true

        let handler = toolHandler
        let setNotRunning = { @MainActor [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            self.isRunning = false
        }
        serverTask = Task.detached {
            let router = Router()
            router.post("mcp") { request, _ -> Response in
                let body = try await request.body.collect(upTo: 1_048_576)
                let data = Data(buffer: body)

                let rpcRequest: JSONRPCRequest
                switch Self.decodeIncomingRequest(data) {
                case .success(let req):
                    rpcRequest = req
                case .failure(let errorResponse):
                    return Self.jsonResponse(errorResponse)
                }

                // Notifications (id member omitted) must not receive a
                // JSON-RPC response body. Explicit "id": null is NOT a
                // notification and is handled by the tool dispatcher.
                guard let rpcResponse = await handler.handle(rpcRequest) else {
                    return Response(status: .accepted)
                }
                return Self.jsonResponse(rpcResponse)
            }

            let app = Application(
                router: router,
                configuration: .init(
                    address: .hostname("127.0.0.1", port: port)
                )
            )

            do {
                try await app.runService()
            } catch {
                // Server stopped or failed to bind
            }
            await setNotRunning()
        }
    }

    func stop() {
        serverTask?.cancel()
        serverTask = nil
        isRunning = false
    }

    // MARK: - Helpers

    /// Result of attempting to decode an incoming request body as JSON-RPC.
    nonisolated enum DecodeOutcome: Sendable {
        case success(JSONRPCRequest)
        case failure(JSONRPCResponse)
    }

    /// Decode an incoming request body as a JSON-RPC request, distinguishing
    /// transport-level parse failures from protocol-level shape failures.
    ///
    /// Per JSON-RPC 2.0 §5.1:
    /// - Returns `.failure` with code `-32700 "Parse error"` when the body is
    ///   not well-formed JSON.
    /// - Returns `.failure` with code `-32600 "Invalid Request"` when the body
    ///   is valid JSON but is not a well-formed Request object (e.g. missing
    ///   `method`, non-string `jsonrpc`, unsupported `id` type, or a non-object
    ///   root).
    /// - Returns `.success` with the decoded request otherwise.
    ///
    /// The error response always uses `id: null` because the id member of a
    /// malformed request cannot be reliably extracted.
    nonisolated static func decodeIncomingRequest(
        _ data: Data
    ) -> DecodeOutcome {
        // Stage 1: confirm the bytes are well-formed JSON. `.fragmentsAllowed`
        // lets scalar roots through so they reach the shape check (and become
        // Invalid Request rather than Parse error).
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(
                with: data, options: [.fragmentsAllowed]
            )
        } catch {
            return .failure(JSONRPCResponse.error(
                id: nil,
                code: JSONRPCErrorCode.parseError,
                message: "Parse error"
            ))
        }

        // A present-but-non-string `jsonrpc` member is a structurally invalid
        // request (-32600), not a parse error. `JSONRPCRequest`'s decoder is
        // intentionally lenient — it coerces a non-string `jsonrpc` to "" so the
        // handler's version check can reject it (T-1106) — so the shape failure
        // is detected here to honor this method's documented contract (T-1128).
        if let object = parsed as? [String: Any],
           object["jsonrpc"] != nil,
           !(object["jsonrpc"] is String) {
            return .failure(JSONRPCResponse.error(
                id: nil,
                code: JSONRPCErrorCode.invalidRequest,
                message: "Invalid Request"
            ))
        }

        // Stage 2: structural decode into JSONRPCRequest. Any failure here is
        // valid JSON with the wrong shape — Invalid Request.
        do {
            let rpcRequest = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
            return .success(rpcRequest)
        } catch {
            return .failure(JSONRPCResponse.error(
                id: nil,
                code: JSONRPCErrorCode.invalidRequest,
                message: "Invalid Request"
            ))
        }
    }

    nonisolated private static func jsonResponse(
        _ response: JSONRPCResponse
    ) -> Response {
        let data: Data
        do {
            data = try JSONEncoder().encode(response)
        } catch {
            let fallback = """
            {"jsonrpc":"2.0","id":null,\
            "error":{"code":-32603,"message":"Encoding failed"}}
            """
            data = Data(fallback.utf8)
        }
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}

#endif
