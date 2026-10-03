#if os(macOS)
import Foundation

nonisolated struct MCPModernServerIdentity: Sendable {
    let name: String
    let version: String
}

nonisolated struct MCPModernToolDescriptor: Sendable {
    let name: String
    let description: String
    let inputSchema: MCPJSONDocument
    let resultSchema: MCPResultSchemaDescriptor
}

/// Discovery/list encoders add modern complete/cache fields after their RED gate.
nonisolated enum MCPModernDiscovery {
    static func encodeDiscovery(id: JSONRPCId, identity: MCPModernServerIdentity) throws -> Data {
        throw MCPResultBoundaryError.notImplemented
    }

    static func encodeTools(id: JSONRPCId, tools: [MCPModernToolDescriptor]) throws -> Data {
        throw MCPResultBoundaryError.notImplemented
    }
}
#endif
