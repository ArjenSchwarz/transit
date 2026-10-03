#if os(macOS)
import Foundation

nonisolated struct MCPClassifiedRead: Sendable {
    let request: MCPReadToolRequest
    let malformedArguments: Bool
}

/// Transport-neutral single-read bridge. Modern protocol validation remains the wire owner's layer.
nonisolated enum MCPBoundedReadDispatcher {
    static func classify(_ rpc: JSONRPCRequest) -> MCPClassifiedRead? {
        guard rpc.jsonrpc == "2.0", !rpc.isNotification, rpc.id != nil, rpc.method == "tools/call",
              let params = rpc.params?.value as? [String: Any], let tool = params["name"] as? String,
              ["query_tasks", "query_milestones", "get_projects"].contains(tool) else { return nil }
        let arguments = params["arguments"] as? [String: Any]
        return MCPClassifiedRead(request: MCPReadToolRequest(tool: tool,
            arguments: (arguments ?? [:]).mapValues(AnyCodable.init)),
            malformedArguments: params["arguments"] != nil && arguments == nil)
    }

    @concurrent static func response(
        for read: MCPClassifiedRead, rpc: JSONRPCRequest, handler: MCPToolHandler,
        coordinator: MCPReadCoordinator, admittedAt: ContinuousClock.Instant,
        encode: @escaping @Sendable (MCPPreparedToolRead, JSONRPCId) throws -> Data = encodeResult
    ) async throws -> Data {
        guard let id = rpc.id else { throw MCPReadCaptureError.serializationFailure }
        let admission = MCPReadAdmission()
        let policy = (read.request.arguments["readPolicy"]?.value as? String).flatMap(MCPReadPolicy.init(rawValue:))
            ?? .refreshIfNeeded
        let timeout = try failure(id: id, operationID: admission.operationID, policy: policy,
                                  category: .timeout, code: "READ_TIMEOUT")
        let busy = try failure(id: id, operationID: admission.operationID, policy: policy,
                               category: .busy, code: "READ_BUSY")
        let serialization = try failure(id: id, operationID: admission.operationID, policy: policy,
            category: .serializationFailure, code: read.request.tool == "query_tasks" ? "QUERY_FAILED" : "READ_FAILED")
        let errors = PreencodedPublicationErrors(busy: busy,
            expired: try queryFailure(id: id, code: "QUERY_EXPIRED"),
            capacity: try queryFailure(id: id, code: "QUERY_CAPACITY_EXCEEDED"))
        return await coordinator.execute(timeout: timeout, busy: busy, admittedAt: admittedAt,
                                         admission: admission) { operation in
            var prepared: MCPPreparedToolRead?
            do {
                if read.malformedArguments {
                    let bytes = try JSONEncoder().encode(JSONRPCResponse.error(id: id,
                        code: JSONRPCErrorCode.invalidParams, message: "Invalid arguments: must be a JSON object"))
                    return PreparedReadResult(encodedResponse: bytes, publications: [], publicationErrors: errors)
                }
                let tool = try await handler.prepareCoveredRead(read.request, operation: operation)
                prepared = tool
                let bytes = try encode(tool, id)
                return PreparedReadResult(encodedResponse: bytes, publications: tool.publications,
                                          publicationErrors: errors)
            } catch {
                if let prepared { discard(prepared.publications, in: coordinator.domain) }
                return PreparedReadResult(encodedResponse: serialization, publications: [], publicationErrors: errors)
            }
        }
    }

    static func encodeResult(_ tool: MCPPreparedToolRead, id: JSONRPCId) throws -> Data {
        var result = Data("{\"jsonrpc\":\"2.0\",\"id\":".utf8)
        result.append(try JSONEncoder().encode(id))
        result.append(Data(",\"result\":".utf8))
        result.append(tool.encodedToolResult)
        result.append(Data("}".utf8))
        return result
    }

    private static func failure(id: JSONRPCId, operationID: UUID, policy: MCPReadPolicy,
                                category: ReadFailureCategory, code: String) throws -> Data {
        let metadata = ReadFailureMetadata(requestId: operationID.uuidString, category: category,
            read: ReadExecutionMetadata(policy: policy, refreshOutcome: .unavailable, budgetMs: 5_000))
        let textBytes = try JSONEncoder().encode(["error": ["code": code, "message": code]])
        guard let text = String(data: textBytes, encoding: .utf8) else {
            throw MCPReadCaptureError.serializationFailure
        }
        return try encodeResult(MCPPreparedToolRead(text: text, isError: true, metadata: .failure(metadata)), id: id)
    }

    private static func queryFailure(id: JSONRPCId, code: String) throws -> Data {
        let bytes = try JSONEncoder().encode(["error": ["code": code, "message": code]])
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw MCPReadCaptureError.serializationFailure
        }
        return try encodeResult(MCPPreparedToolRead(text: text, isError: true), id: id)
    }

    private static func discard(_ publications: [any MCPPreparedPublication], in domain: MCPReadPublicationDomain) {
        let (_, retired) = domain.withLockRetainingRetirement {
            for publication in publications { publication.discardLocked(in: domain) }
        }
        withExtendedLifetime(retired) {}
    }
}
#endif
