#if os(macOS)
import Foundation

/// Frozen tool-level fragments never retain the originating JSON-RPC ID.
nonisolated struct MCPResultToolFragment: Sendable {
    let encodedResult: Data
}

/// Encoder boundaries return complete immutable response bytes, not closures.
nonisolated enum MCPResultEncoder {
    static func encode(
        source: MCPResultSource,
        presentation: MCPResultPresentation,
        id: JSONRPCId,
        metadata: MCPResultMetadata?
    ) throws -> Data {
        throw MCPResultBoundaryError.notImplemented
    }

    static func prepareMutationFallback(
        id: JSONRPCId,
        source: MCPResultSource,
        context: MCPResultContext,
        metadata: MCPResultMetadata?
    ) throws -> Data {
        throw MCPResultBoundaryError.notImplemented
    }

    static func freeze(
        source: MCPResultSource,
        presentation: MCPResultPresentation,
        metadata: MCPResultMetadata?
    ) throws -> MCPResultToolFragment {
        throw MCPResultBoundaryError.notImplemented
    }

    static func encode(fragment: MCPResultToolFragment, id: JSONRPCId) throws -> Data {
        throw MCPResultBoundaryError.notImplemented
    }
}
#endif
