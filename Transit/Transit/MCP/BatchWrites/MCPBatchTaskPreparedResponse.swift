#if os(macOS)
import Foundation

/// Required capability for future batch execution. Only successful preparation
/// of complete correlated bytes can construct it; it retains no encoder callback.
nonisolated struct MCPBatchTaskPreparedResponse: Sendable {
    private let id: JSONRPCId
    private let fixedContext: MCPResultContext
    private let metadata: MCPResultMetadata?
    private let fallbackSource: MCPResultSource
    private let readyBytes: Data

    var context: MCPResultContext { fixedContext }

    private init(id: JSONRPCId, context: MCPResultContext, metadata: MCPResultMetadata?,
                 fallbackSource: MCPResultSource, readyBytes: Data) {
        self.id = id
        self.fixedContext = context
        self.metadata = metadata
        self.fallbackSource = fallbackSource
        self.readyBytes = readyBytes
    }

    static func prepare(
        id: JSONRPCId, items: [MCPBatchRecoveryItem], metadata: MCPResultMetadata?,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> MCPBatchTaskPreparedResponse {
        try checkpoint()
        let source = try MCPBatchTaskFallback.source(items: items)
        let context = MCPResultContext(tool: "mutate_tasks", semanticFailure: nil,
                                       mutationRecovery: .applicationBatch(items: items), entityPositions: [])
        let bytes = try MCPResultEncoder.prepareMutationFallback(id: id, source: source,
            context: context, metadata: metadata, checkpoint: checkpoint)
        return MCPBatchTaskPreparedResponse(id: id, context: context, metadata: metadata,
                                            fallbackSource: source, readyBytes: bytes)
    }

    /// The delivered common selector still owns identity validation and delivery
    /// suppression. Its preparation callback only selects these immutable bytes.
    func select(
        encodeOutcome: MCPResultProviderSelection.EncodeOutcome = MCPResultProviderSelection.encode,
        shouldDeliver: @escaping @Sendable () -> Bool = { !Task.isCancelled },
        dispatch: @escaping @Sendable () async throws -> MCPResultProviderOutcome
    ) async throws -> MCPResultResponseSelection {
        let prepared = readyBytes
        return try await MCPResultProviderSelection.mutation(id: id, context: fixedContext,
            metadata: metadata, fallbackSource: fallbackSource, prepareFallback: { _, _, _, _ in prepared },
            encodeOutcome: encodeOutcome, shouldDeliver: shouldDeliver, dispatch: dispatch)
    }
}
#endif
