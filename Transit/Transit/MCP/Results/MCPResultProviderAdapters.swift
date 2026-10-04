#if os(macOS)
import Foundation

/// Declarations made where a provider produces its result, not inferred from parsing failure.
/// These values are never encoded into original logical JSON or persisted receipts.
nonisolated struct MCPResultProviderEvidence: Sendable {
    let origin: MCPResultOrigin
    let evidence: MCPResultEvidence
    let failure: MCPResultFailure?
    let requiresPreparedReconciliation: Bool

    init(origin: MCPResultOrigin, evidence: MCPResultEvidence = .established,
         failure: MCPResultFailure? = nil, requiresPreparedReconciliation: Bool = false) {
        self.origin = origin
        self.evidence = evidence
        self.failure = failure
        self.requiresPreparedReconciliation = requiresPreparedReconciliation
    }
}

/// Value-only provider adaptation. This layer does not read storage or decide acceptance.
nonisolated enum MCPResultProviderAdapters {
    static func outcome(
        result: MCPToolResult,
        context: MCPResultContext,
        origin: MCPResultOrigin,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> MCPResultProviderOutcome {
        try checkpoint()
        let declaration = result.providerEvidence
        guard declaration?.requiresPreparedReconciliation != true,
              result.content.count == 1, let content = result.content.first, content.type == "text" else {
            throw MCPResultBoundaryError.unsupportedEvidence
        }
        let source = try MCPResultAdapter.source(text: content.text, isError: result.isError,
            origin: declaration?.origin ?? origin, evidence: declaration?.evidence ?? .established,
            checkpoint: checkpoint)
        let effective = MCPResultContext(tool: context.tool,
            semanticFailure: declaration?.failure ?? context.semanticFailure,
            mutationRecovery: context.mutationRecovery, entityPositions: context.entityPositions)
        return MCPResultProviderOutcome(source: source, context: effective)
    }

    /// Frozen capture metadata remains an opaque value in its existing namespace.
    static func metadata(
        result: MCPToolResult,
        frozenReadBytes: Data? = nil,
        checkpoint: @escaping @Sendable () throws -> Void = {}
    ) throws -> MCPResultMetadata? {
        try checkpoint()
        let bytes: Data
        if let frozenReadBytes {
            var wrapper = MCPResultByteWriter(checkpoint: checkpoint)
            try wrapper.literal("{\"me.nore.ig.transit/read\":")
            try wrapper.raw(frozenReadBytes)
            try wrapper.literal("}")
            bytes = wrapper.data
        } else if let metadata = result.metadata {
            bytes = try JSONEncoder().encode(metadata)
        } else { return nil }
        let document = try MCPJSONDocument.parse(bytes, checkpoint: checkpoint)
        return try MCPResultMetadata.make(document: document, checkpoint: checkpoint)
    }
}
#endif
