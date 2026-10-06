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
              ["query_tasks", "query_milestones", "get_projects", "query_project_summaries"].contains(tool)
                || MCPConsolidationToolDefinitions.previewTools.contains(tool)
        else { return nil }
        let arguments = params["arguments"] as? [String: Any]
        return MCPClassifiedRead(request: MCPReadToolRequest(tool: tool,
            arguments: (arguments ?? [:]).mapValues(AnyCodable.init)),
            malformedArguments: params["arguments"] != nil && arguments == nil)
    }

    @concurrent static func response(
        for read: MCPClassifiedRead, rpc: JSONRPCRequest, handler: MCPToolHandler,
        coordinator: MCPReadCoordinator, admittedAt: ContinuousClock.Instant,
        admissionOwner: MCPReadAdmissionOwner = .application,
        encode: @escaping @Sendable (MCPPreparedToolRead, JSONRPCId) throws -> Data = encodeResult,
        encodeWithOperation: (@Sendable (MCPPreparedToolRead, JSONRPCId, MCPReadOperation) throws -> Data)? = nil,
        encodeConstantToolFailure: (@Sendable (MCPPreparedToolRead, JSONRPCId) throws -> Data)? = nil
    ) async throws -> Data {
        guard let id = rpc.id else { throw MCPReadCaptureError.serializationFailure }
        let constantEncoder = encodeConstantToolFailure ?? encodeResult
        let admission = MCPReadAdmission(owner: admissionOwner)
        let policy = (read.request.arguments["readPolicy"]?.value as? String).flatMap(MCPReadPolicy.init(rawValue:))
            ?? .refreshIfNeeded
        let timeout = try failure(id: id, operationID: admission.operationID, policy: policy,
                                  category: .timeout, code: "READ_TIMEOUT", encode: constantEncoder)
        let busy = try failure(id: id, operationID: admission.operationID, policy: policy,
                               category: .busy, code: "READ_BUSY", encode: constantEncoder)
        let serialization = try failure(id: id, operationID: admission.operationID, policy: policy,
            category: .serializationFailure, code: read.request.tool == "query_tasks" ? "QUERY_FAILED" : "READ_FAILED",
            encode: constantEncoder)
        let errors = try publicationErrors(for: read.request, id: id, busy: busy,
                                           encodeConstantToolFailure: constantEncoder)
        return await coordinator.execute(timeout: timeout, busy: busy, admittedAt: admittedAt,
                                         admission: admission, diagnosticTool: read.request.tool) { operation in
            var prepared: MCPPreparedToolRead?
            do {
                if read.malformedArguments {
                    let bytes = try JSONEncoder().encode(JSONRPCResponse.error(id: id,
                        code: JSONRPCErrorCode.invalidParams, message: "Invalid arguments: must be a JSON object"))
                    return PreparedReadResult(encodedResponse: bytes, publications: [], publicationErrors: errors,
                                              diagnosticOutcome: .failure)
                }
                operation.beginActorQueue()
                let tool = try await handler.prepareCoveredRead(read.request, operation: operation)
                prepared = tool
                let bytes = try encodeMeasured(tool, id: id, operation: operation) { tool, id, operation in
                    try encodeWithOperation?(tool, id, operation) ?? encode(tool, id)
                }
                return PreparedReadResult(encodedResponse: bytes, publications: tool.publications,
                    publicationErrors: errors, diagnosticOutcome: tool.result.isError == true ? .failure : .success)
            } catch {
                if let prepared { discard(prepared.publications, in: coordinator.domain) }
                return PreparedReadResult(encodedResponse: serialization, publications: [],
                                          publicationErrors: errors, diagnosticOutcome: .failure)
            }
        }
    }

    /// Measures the actual complete RPC encoder outside the publication gate and on the original operation.
    static func encodeMeasured(_ tool: MCPPreparedToolRead, id: JSONRPCId, operation: MCPReadOperation,
                               encode: @Sendable (MCPPreparedToolRead, JSONRPCId, MCPReadOperation) throws -> Data)
        throws -> Data {
        let started = ContinuousClock.now
        do {
            let bytes = try encode(tool, id, operation)
            operation.recordDiagnostic(.serialization, startedAt: started)
            return bytes
        } catch {
            operation.recordDiagnostic(.serialization, startedAt: started, outcome: .failure)
            throw error
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

    /// Prepares transport errors before the terminal gate; retention families own distinct expiry codes.
    static func publicationErrors(for request: MCPReadToolRequest, id: JSONRPCId,
                                  busy: Data,
                                  encodeConstantToolFailure:
                                    (@Sendable (MCPPreparedToolRead, JSONRPCId) throws -> Data)? = nil
    ) throws -> PreencodedPublicationErrors {
        let constantEncoder = encodeConstantToolFailure ?? encodeResult
        let expiryCode: String
        if request.tool == "query_project_summaries" {
            expiryCode = request.arguments["cursor"] == nil ? "INVALID_SNAPSHOT" : "INVALID_CURSOR"
        } else if request.tool == "query_tasks", request.arguments["snapshotId"] != nil {
            expiryCode = "INVALID_SNAPSHOT"
        } else if request.tool == "query_tasks",
                  let cursor = request.arguments["cursor"]?.value as? String,
                  MCPCursorFamily.classify(cursor) == .reusable {
            expiryCode = "INVALID_CURSOR"
        } else {
            expiryCode = "QUERY_EXPIRED"
        }
        return PreencodedPublicationErrors(busy: busy,
            expired: try queryFailure(id: id, code: expiryCode, encode: constantEncoder),
            capacity: try queryFailure(id: id, code: "QUERY_CAPACITY_EXCEEDED", encode: constantEncoder))
    }

    // The encoder is separate from failure identity/category to keep fallback preparation independent.
    // swiftlint:disable:next function_parameter_count
    private static func failure(id: JSONRPCId, operationID: UUID, policy: MCPReadPolicy,
                                category: ReadFailureCategory, code: String,
                                encode: @Sendable (MCPPreparedToolRead, JSONRPCId) throws -> Data) throws -> Data {
        let metadata = ReadFailureMetadata(requestId: operationID.uuidString, category: category,
            read: ReadExecutionMetadata(policy: policy, refreshOutcome: .unavailable, budgetMs: 5_000))
        let textBytes = try JSONEncoder().encode(["error": ["code": code, "message": code]])
        guard let text = String(data: textBytes, encoding: .utf8) else {
            throw MCPReadCaptureError.serializationFailure
        }
        return try encode(MCPPreparedToolRead(text: text, isError: true, metadata: .failure(metadata)), id)
    }

    private static func queryFailure(id: JSONRPCId, code: String,
                                     encode: @Sendable (MCPPreparedToolRead, JSONRPCId) throws -> Data) throws -> Data {
        let bytes = try JSONEncoder().encode(["error": ["code": code, "message": code]])
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw MCPReadCaptureError.serializationFailure
        }
        return try encode(MCPPreparedToolRead(text: text, isError: true), id)
    }

    private static func discard(_ publications: [any MCPPreparedPublication], in domain: MCPReadPublicationDomain) {
        let (_, retired) = domain.withLockRetainingRetirement {
            for publication in publications { publication.discardLocked(in: domain) }
        }
        withExtendedLifetime(retired) {}
    }
}
#endif
