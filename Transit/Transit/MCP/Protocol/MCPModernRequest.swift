#if os(macOS)
import Foundation

/// Ordered headers retain duplicates so validation can reject conflicts.
nonisolated struct MCPModernHeader: Sendable {
    let name: String
    let value: String
}

nonisolated struct MCPModernRequestInput: Sendable {
    let httpMethod: String
    let headers: [MCPModernHeader]
    let body: Data
}

nonisolated enum MCPModernToolExecution: Sendable {
    case coveredRead, ordinaryRead, protectedWrite, applicationBatch, unprotectedMaintenance
}

nonisolated struct MCPModernAvailableTool: Sendable {
    let name: String
    let execution: MCPModernToolExecution
}

/// No storage/actor callbacks occur during pre-admission classification.
nonisolated struct MCPModernAvailability: Sendable {
    let tools: [MCPModernAvailableTool]
}

nonisolated struct MCPModernClientMetadata: Sendable {
    let protocolVersion: String
    let clientCapabilities: MCPJSONValue
    let clientInfo: MCPJSONValue?
}

nonisolated enum MCPModernMethod: Sendable {
    case discover
    case listTools
    case callTool(name: String, execution: MCPModernToolExecution)
    case listenSubscriptions
}

nonisolated struct MCPModernRequest: Sendable {
    let id: JSONRPCId
    let method: MCPModernMethod
    let params: MCPJSONValue?
    let metadata: MCPModernClientMetadata
    let document: MCPJSONDocument
}

/// Pure HTTP/RPC rejection data; notifications do not acquire response IDs.
nonisolated struct MCPModernRejection: Error, Sendable {
    let httpStatus: Int
    let rpcCode: Int?
    let message: String
    let id: JSONRPCId?
    let data: MCPJSONValue?
}
#endif
