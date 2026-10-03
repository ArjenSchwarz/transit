#if os(macOS)
import Foundation
import Hummingbird
import NIOCore
import NIOFoundationCompat

extension MCPServer {

    /// Builds the Hummingbird router for the MCP endpoint.
    /// POST carries JSON-RPC; GET offers the optional Streamable HTTP SSE
    /// channel used for server-initiated notifications.
    /// `nonisolated` keeps transport construction independent of MainActor;
    /// route callbacks execute on Hummingbird/NIO and hop to MainActor when dispatching.
    nonisolated static func makeRouter(
        handler: MCPToolHandler, readCoordinator: MCPReadCoordinator? = nil
    ) -> Router<MCPRequestContext> {
        let coordinator = readCoordinator ?? handler.readCoordinator
        let router = Router(context: MCPRequestContext.self)
        router.get("mcp") { request, context -> Response in
            guard Self.isAllowedMCPRequest(request) else { return forbiddenResponse() }
            return await Self.toolListChangeStreamResponse(
                request: request,
                context: context,
                handler: handler
            )
        }
        router.post("mcp") { request, _ -> Response in
            // Validate origin before reading the body.
            guard Self.isAllowedMCPRequest(request) else { return forbiddenResponse() }

            let body = try await request.body.collect(upTo: 1_048_576)
            let data = Data(buffer: body)

            switch decodeIncomingRequest(data) {
            case .success(let rpcRequest):
                let admittedAt = ContinuousClock.now
                if let read = MCPBoundedReadDispatcher.classify(rpcRequest) {
                    let bytes = try await MCPBoundedReadDispatcher.response(for: read, rpc: rpcRequest,
                        handler: handler, coordinator: coordinator, admittedAt: admittedAt)
                    return Response(status: .ok, headers: [.contentType: "application/json"],
                                    body: .init(byteBuffer: ByteBuffer(data: bytes)))
                }
                // A single notification has no JSON-RPC response body.
                guard let rpcResponse = await handler.handle(rpcRequest) else {
                    return Response(status: .accepted)
                }
                if rpcRequest.method == "initialize", rpcResponse.error == nil {
                    let sessionID = await handler.createToolListChangeSession()
                    return jsonResponse(
                        rpcResponse,
                        additionalHeaders: [.mcpSessionID: sessionID]
                    )
                }
                return jsonResponse(rpcResponse)

            case .batch(let elements):
                return await batchResponse(for: elements, handler: handler)

            case .failure(let errorResponse):
                return jsonResponse(errorResponse)
            }
        }
        return router
    }

    /// Dispatches one non-empty JSON-RPC batch and builds its HTTP response.
    private static func batchResponse(
        for elements: [BatchElement],
        handler: MCPToolHandler
    ) async -> Response {
        var responses: [JSONRPCResponse] = []
        responses.reserveCapacity(elements.count)

        // Sequential dispatch is intentional. JSON-RPC permits any processing
        // order, and preserving input order keeps side effects deterministic
        // for Transit's shared model context.
        for element in elements {
            switch element {
            case .invalid:
                responses.append(invalidRequestResponse())
            case .request(let rpcRequest):
                // MCP 2025-03-26 lifecycle: initialize MUST NOT be in a batch.
                // Notifications still never get a response.
                if rpcRequest.method == "initialize" {
                    if !rpcRequest.isNotification {
                        responses.append(JSONRPCResponse.error(
                            id: rpcRequest.id,
                            code: JSONRPCErrorCode.invalidRequest,
                            message: "Invalid Request: initialize must not be batched"
                        ))
                    }
                } else if let rpcResponse = await handler.handle(rpcRequest) {
                    responses.append(rpcResponse)
                }
            }
        }

        // JSON-RPC forbids an empty response array. Streamable HTTP requires
        // 202 with no body when the input is notifications only.
        guard !responses.isEmpty else {
            return Response(status: .accepted)
        }
        return jsonResponse(responses)
    }

    // MARK: - Helpers

    /// Decode an incoming request body as a single JSON-RPC request or a
    /// non-empty JSON-RPC batch, distinguishing transport-level parse failures
    /// from protocol-level shape failures.
    ///
    /// Per JSON-RPC 2.0 §5.1 and §6:
    /// - Malformed JSON produces one `-32700 Parse error` response.
    /// - An invalid single root or an empty batch produces one `-32600 Invalid
    ///   Request` response object.
    /// - A non-empty batch preserves every member. Valid request objects are
    ///   dispatched, while each invalid member produces its own `-32600`
    ///   response in the eventual response array.
    nonisolated static func decodeIncomingRequest(
        _ data: Data
    ) -> DecodeOutcome {
        // Stage 1: confirm the bytes are well-formed JSON. `.fragmentsAllowed`
        // lets scalar roots through so they become Invalid Request rather than
        // Parse error.
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

        if let batch = parsed as? [Any] {
            guard !batch.isEmpty else {
                return .failure(invalidRequestResponse())
            }
            return .batch(batch.map { element in
                guard let object = element as? [String: Any],
                      let request = decodeRequestObject(object) else {
                    return .invalid
                }
                return .request(request)
            })
        }

        guard let object = parsed as? [String: Any],
              isValidRequestObjectShape(object),
              let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
            return .failure(invalidRequestResponse())
        }
        return .success(request)
    }

    /// Structural checks that `JSONRPCRequest` intentionally leaves lenient.
    /// A missing `jsonrpc` member decodes to `""` so the handler can preserve
    /// T-1106's detailed version error, but a present non-string member is not
    /// a valid Request object. Likewise, present `params` must be the structured
    /// object or array required by JSON-RPC 2.0 §4.2.
    nonisolated private static func isValidRequestObjectShape(
        _ object: [String: Any]
    ) -> Bool {
        guard object["jsonrpc"] == nil || object["jsonrpc"] is String else {
            return false
        }
        guard let params = object["params"] else {
            return true
        }
        return params is [String: Any] || params is [Any]
    }

    nonisolated private static func decodeRequestObject(
        _ object: [String: Any]
    ) -> JSONRPCRequest? {
        guard isValidRequestObjectShape(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return try? JSONDecoder().decode(JSONRPCRequest.self, from: data)
    }

    nonisolated private static func invalidRequestResponse() -> JSONRPCResponse {
        JSONRPCResponse.error(
            id: nil,
            code: JSONRPCErrorCode.invalidRequest,
            message: "Invalid Request"
        )
    }

    /// Validates Origin and Host/authority before body access or dispatch.
    /// This MCP DNS-rebinding defence must remain first in every MCP route.
    nonisolated private static func isAllowedMCPRequest(_ request: Request) -> Bool {
        let origin = request.head.headerFields[.origin]
        return MCPOriginValidator.rejectionReason(
            origin: origin,
            authority: request.head.authority
        ) == nil
    }

    /// Transport-level rejection, not JSON-RPC: fixed plain text avoids
    /// revealing whether Origin or Host validation failed to a prober.
    nonisolated private static func forbiddenResponse() -> Response {
        Response(
            status: .forbidden,
            headers: [.contentType: "text/plain"],
            body: .init(byteBuffer: ByteBuffer(string: "Forbidden"))
        )
    }

}
#endif
