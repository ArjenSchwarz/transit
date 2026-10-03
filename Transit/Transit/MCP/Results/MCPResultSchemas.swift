#if os(macOS)
import Foundation

/// Descriptor data is independent of shared tool-definition registration.
nonisolated struct MCPResultSchemaDescriptor: Sendable {
    let tool: String
    let description: String
    let outputSchema: MCPJSONDocument
}

nonisolated enum MCPResultSchemas {
    static func descriptor(tool: String, description: String) throws -> MCPResultSchemaDescriptor {
        throw MCPResultBoundaryError.notImplemented
    }
}
#endif
