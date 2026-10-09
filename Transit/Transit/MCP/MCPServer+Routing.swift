#if os(macOS)
import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import NIOFoundationCompat

extension MCPServer {
    private nonisolated struct DispatchSnapshot {
        let maintenanceEnabled: Bool
        let admittedAt: ContinuousClock.Instant
        let owner: MCPReadAdmissionOwner
    }

    /// Modern single-request transport. Availability is frozen before covered admission.
    nonisolated static func makeRouter(
        handler: MCPToolHandler, readCoordinator: MCPReadCoordinator? = nil,
        admissionOwner: MCPReadAdmissionOwner = .application
    ) -> Router<MCPRequestContext> {
        let coordinator = readCoordinator ?? handler.readCoordinator
        let router = Router(context: MCPRequestContext.self)
        let methods: [HTTPRequest.Method] = [.get, .delete, .head, .put, .patch, .options, .trace, .connect]
        for method in methods {
            router.on("mcp", method: method) { request, _ -> Response in
                guard Self.isAllowedMCPRequest(request) else { return forbiddenResponse() }
                return Response(status: .methodNotAllowed, headers: [.allow: "POST"])
            }
        }
        router.post("mcp") { request, context -> Response in
            await modernPost(request, context: context, handler: handler,
                coordinator: coordinator, admissionOwner: admissionOwner)
        }
        return router
    }

    nonisolated private static func modernPost(_ request: Request, context: MCPRequestContext, handler: MCPToolHandler,
                                               coordinator: MCPReadCoordinator,
                                               admissionOwner: MCPReadAdmissionOwner) async -> Response {
        guard Self.isAllowedMCPRequest(request) else { return forbiddenResponse() }
        var headers = request.head.headerFields.map {
            MCPModernHeader(name: $0.name.rawName, value: $0.value)
        }
        if !headers.contains(where: { $0.name.lowercased() == "host" }), let authority = request.head.authority {
            headers.append(MCPModernHeader(name: "Host", value: authority))
        }
        do {
            try MCPModernValidator.validateTransport(MCPModernRequestInput(httpMethod: "POST",
                headers: headers, body: Data()))
            let body = try await request.body.collect(upTo: 1_048_576)
            let maintenanceEnabled = handler.modernMaintenanceEnabled
            let modern = try MCPModernValidator.validate(MCPModernRequestInput(httpMethod: "POST",
                headers: headers, body: Data(buffer: body)),
                availability: MCPModernProviderBinding.availability(maintenanceEnabled: maintenanceEnabled,
                    consolidationEnabled: handler.consolidationCapabilityInstalled))
            let admittedAt = ContinuousClock.now
            return try await dispatchModern(modern, context: context, handler: handler, coordinator: coordinator,
                snapshot: DispatchSnapshot(maintenanceEnabled: maintenanceEnabled,
                    admittedAt: admittedAt, owner: admissionOwner))
        } catch let rejection as MCPModernRejection {
            return modernRejection(rejection)
        } catch let transport as HTTPError {
            return Response(status: transport.status, headers: transport.headers)
        } catch {
            return Response(status: .internalServerError)
        }
    }

    nonisolated private static func dispatchModern(
        _ modern: MCPModernRequest, context: MCPRequestContext, handler: MCPToolHandler,
        coordinator: MCPReadCoordinator, snapshot: DispatchSnapshot
    ) async throws -> Response {
        let maintenanceEnabled = snapshot.maintenanceEnabled
        let admittedAt = snapshot.admittedAt, admissionOwner = snapshot.owner
        switch modern.method {
        case .discover:
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            return encodedResponse(try MCPModernDiscovery.encodeDiscovery(id: modern.id,
                identity: MCPModernServerIdentity(name: AppPersistencePolicy.serverName, version: version)))
        case .listTools:
            return encodedResponse(try MCPModernDiscovery.encodeTools(id: modern.id,
                tools: MCPToolDefinitions.modernTools(includingMaintenance: maintenanceEnabled,
                    includingConsolidation: handler.consolidationCapabilityInstalled)))
        case .callTool(let tool, let execution):
            // Batch shape and numeric tokens must reach the parser before Any conversion.
            if case .applicationBatch = execution {
                return selectedResponse(try await MCPBatchModernProvider.call(modern, handler: handler))
            }
            let rpc = MCPModernWire.request(modern, tool: tool)
            if case .coveredRead = execution {
                guard let read = MCPBoundedReadDispatcher.classify(rpc) else {
                    throw MCPResultBoundaryError.unsupportedEvidence
                }
                let bytes = try await MCPBoundedReadDispatcher.response(for: read, rpc: rpc,
                    handler: handler, coordinator: coordinator, admittedAt: admittedAt, admissionOwner: admissionOwner,
                    encodeWithOperation: { prepared, id, operation in
                        try MCPModernProviderBinding.read(prepared, id: id, tool: tool, operation: operation)
                    }, encodeConstantToolFailure: { prepared, id in
                        try MCPModernProviderBinding.read(prepared, id: id, tool: tool)
                    })
                return encodedResponse(bytes)
            }
            return selectedResponse(try await MCPModernProviderBinding.call(rpc, tool: tool, handler: handler,
                maintenanceEnabled: maintenanceEnabled))
        case .listenSubscriptions:
            do {
                return try await toolListChangeStreamResponse(modern: modern, context: context, handler: handler)
            } catch MCPSubscriptionRegistrationError.closed {
                return modernRejection(MCPModernRejection(httpStatus: 503, rpcCode: -32603,
                    message: "Subscriptions are closing", id: modern.id, data: nil))
            }
        }
    }

    nonisolated private static func selectedResponse(_ selection: MCPResultResponseSelection) -> Response {
        switch selection {
        case .normal(let bytes), .reconciliation(let bytes): return encodedResponse(bytes)
        case .suppressed: return Response(status: .accepted)
        }
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
