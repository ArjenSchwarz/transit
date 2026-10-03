#if os(macOS)
import Foundation

/// Frozen tool-level fragments never retain the originating JSON-RPC ID.
nonisolated struct MCPResultToolFragment: Sendable {
    let encodedResult: Data

    fileprivate init(encodedResult: Data) {
        self.encodedResult = encodedResult
    }
}

/// Encoder boundaries return complete immutable response bytes, not closures.
nonisolated enum MCPResultEncoder {
    static func encode(
        source: MCPResultSource,
        presentation: MCPResultPresentation,
        id: JSONRPCId,
        metadata: MCPResultMetadata?,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> Data {
        throw MCPResultBoundaryError.notImplemented
    }

    static func prepareMutationFallback(
        id: JSONRPCId,
        source: MCPResultSource,
        context: MCPResultContext,
        metadata: MCPResultMetadata?,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> Data {
        throw MCPResultBoundaryError.notImplemented
    }

    static func freeze(
        source: MCPResultSource,
        presentation: MCPResultPresentation,
        metadata: MCPResultMetadata?,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> MCPResultToolFragment {
        throw MCPResultBoundaryError.notImplemented
    }

    static func encode(
        fragment: MCPResultToolFragment,
        id: JSONRPCId,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> Data {
        throw MCPResultBoundaryError.notImplemented
    }
}
#endif
