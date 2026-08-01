#if os(macOS)

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

#endif
