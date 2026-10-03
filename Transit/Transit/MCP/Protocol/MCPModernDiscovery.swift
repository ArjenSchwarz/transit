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

/// These complete RPC values are distinct from tool-result/fallback encoding.
/// Schema bytes are inserted only from parser-validated immutable documents.
nonisolated enum MCPModernDiscovery {
    static func encodeDiscovery(id: JSONRPCId, identity: MCPModernServerIdentity) throws -> Data {
        var bytes = try prefix(id: id)
        bytes.append(Data("{\"resultType\":\"complete\",\"supportedVersions\":[\"2026-07-28\"],".utf8))
        bytes.append(Data("\"capabilities\":{\"tools\":{\"listChanged\":true}},".utf8))
        bytes.append(Data("\"_meta\":{\"io.modelcontextprotocol/serverInfo\":{\"name\":".utf8))
        bytes.append(try JSONEncoder().encode(identity.name))
        bytes.append(Data(",\"version\":".utf8))
        bytes.append(try JSONEncoder().encode(identity.version))
        bytes.append(Data("}},\"ttlMs\":0,\"cacheScope\":\"public\"}}".utf8))
        return bytes
    }

    static func encodeTools(id: JSONRPCId, tools: [MCPModernToolDescriptor]) throws -> Data {
        var bytes = try prefix(id: id)
        bytes.append(Data("{\"resultType\":\"complete\",\"tools\":[".utf8))
        for (index, tool) in tools.sorted(by: { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }).enumerated() {
            if index > 0 { bytes.append(0x2C) }
            bytes.append(Data("{\"name\":".utf8))
            bytes.append(try JSONEncoder().encode(tool.name))
            bytes.append(Data(",\"description\":".utf8))
            bytes.append(try JSONEncoder().encode(tool.description))
            bytes.append(Data(",\"inputSchema\":".utf8))
            bytes.append(tool.inputSchema.originalUTF8)
            bytes.append(Data(",\"outputSchema\":".utf8))
            bytes.append(tool.resultSchema.outputSchema.originalUTF8)
            bytes.append(0x7D)
        }
        bytes.append(Data("],\"ttlMs\":0,\"cacheScope\":\"public\"}}".utf8))
        return bytes
    }

    private static func prefix(id: JSONRPCId) throws -> Data {
        var bytes = Data("{\"jsonrpc\":\"2.0\",\"id\":".utf8)
        bytes.append(try JSONEncoder().encode(id))
        bytes.append(Data(",\"result\":".utf8))
        return bytes
    }
}
#endif
