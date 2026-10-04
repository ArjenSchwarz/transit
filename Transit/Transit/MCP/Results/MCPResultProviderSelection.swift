#if os(macOS)
import Foundation

/// Immutable evidence returned by a provider; adaptation never recreates saved outcomes.
nonisolated struct MCPResultProviderOutcome: Sendable {
    let source: MCPResultSource
    let context: MCPResultContext
}

nonisolated enum MCPResultResponseSelection: Sendable {
    case normal(Data)
    case reconciliation(Data)
    /// Delivery suppression says nothing about provider acceptance or commitment.
    case suppressed
}

/// Effect-aware response selection only. Providers retain all transaction/recovery ownership.
nonisolated enum MCPResultProviderSelection {
    typealias PrepareFallback = @Sendable (
        JSONRPCId, MCPResultSource, MCPResultContext, MCPResultMetadata?
    ) throws -> Data
    typealias EncodeOutcome = @Sendable (
        MCPResultProviderOutcome, JSONRPCId, MCPResultMetadata?
    ) throws -> Data

    /// `context` fixes the authentic tool/recovery identities before dispatch. Outcome context
    /// may declare source positions/failure phase, but must not substitute those identities.
    /// `metadata` is authoritative for both responses; its original bytes remain opaque.
    /// Fallback preparation must finish before dispatch. Later failures select ready bytes;
    /// cancellation suppresses delivery independently of effects. No callback is retained.
    static func mutation(
        id: JSONRPCId,
        context: MCPResultContext,
        metadata: MCPResultMetadata?,
        fallbackSource: MCPResultSource,
        prepareFallback: PrepareFallback = prepare,
        encodeOutcome: EncodeOutcome = encode,
        shouldDeliver: @escaping @Sendable () -> Bool = { !Task.isCancelled },
        dispatch: @escaping @Sendable () async throws -> MCPResultProviderOutcome
    ) async throws -> MCPResultResponseSelection {
        throw MCPResultBoundaryError.notImplemented
    }

    static func prepare(id: JSONRPCId, source: MCPResultSource, context: MCPResultContext,
                        metadata: MCPResultMetadata?) throws -> Data {
        try MCPResultEncoder.prepareMutationFallback(id: id, source: source,
                                                     context: context, metadata: metadata)
    }

    static func encode(outcome: MCPResultProviderOutcome, id: JSONRPCId,
                       metadata: MCPResultMetadata?) throws -> Data {
        let presentation = try MCPResultAdapter.present(outcome.source, context: outcome.context)
        return try MCPResultEncoder.encode(source: outcome.source, presentation: presentation,
                                            id: id, metadata: metadata)
    }
}
#endif
