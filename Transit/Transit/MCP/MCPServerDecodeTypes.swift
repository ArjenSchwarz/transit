#if os(macOS)

// Nested in `MCPServer` rather than declared at module scope: `DecodeOutcome`
// and `BatchElement` are generic enough names that they would collide badly in
// the app namespace, and they only describe this server's decode step. They sit
// in their own file to keep `MCPServer.swift` under the file-length limit.
extension MCPServer {

    /// Result of decoding an incoming body as one JSON-RPC request or a batch.
    nonisolated enum DecodeOutcome: Sendable {
        case success(JSONRPCRequest)
        case batch([BatchElement])
        case failure(JSONRPCResponse)
    }

    /// One member of a non-empty JSON-RPC batch. Invalid members stay in the
    /// sequence so the route can emit one -32600 response for each of them.
    nonisolated enum BatchElement: Sendable {
        case request(JSONRPCRequest)
        case invalid
    }
}

#endif
