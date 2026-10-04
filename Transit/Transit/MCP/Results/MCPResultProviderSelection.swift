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
        guard shouldDeliver() else { return .suppressed }
        let prepared = try prepareFallback(id, fallbackSource, context, metadata)
        guard shouldDeliver() else { return .suppressed }
        do {
            let outcome = try await dispatch()
            guard shouldDeliver() else { return .suppressed }
            guard sameIdentity(context, outcome.context) else {
                throw MCPResultBoundaryError.unsupportedEvidence
            }
            let bytes = try encodeOutcome(outcome, id, metadata)
            return shouldDeliver() ? .normal(bytes) : .suppressed
        } catch {
            return shouldDeliver() ? .reconciliation(prepared) : .suppressed
        }
    }

    /// Compare opaque identities by UTF8, preserving distinct Unicode spellings and item order.
    private static func sameIdentity(_ fixed: MCPResultContext, _ outcome: MCPResultContext) -> Bool {
        guard exact(fixed.tool, outcome.tool) else { return false }
        switch (fixed.mutationRecovery, outcome.mutationRecovery) {
        case (nil, nil): return true
        case (.protectedWrite(let left), .protectedWrite(let right)):
            return sameKey(left, right)
        case (.unprotectedMaintenance(let left), .unprotectedMaintenance(let right)):
            return exact(left, right)
        case (.applicationBatch(let left), .applicationBatch(let right)):
            guard left.count == right.count else { return false }
            return zip(left, right).allSatisfy { first, second in
                first.index == second.index && exact(first.itemId, second.itemId)
                    && exact(first.operation, second.operation) && sameKey(first.originalKey, second.originalKey)
                    && first.targetTaskId == second.targetTaskId
            }
        default: return false
        }
    }

    private static func sameKey(_ left: MCPProtectedRecoveryKey, _ right: MCPProtectedRecoveryKey) -> Bool {
        exact(left.tool, right.tool) && exact(left.idempotencyKey, right.idempotencyKey)
    }

    private static func exact(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }

    private static func exact(_ left: String?, _ right: String?) -> Bool {
        switch (left, right) {
        case (nil, nil): return true
        case (.some(let first), .some(let second)): return exact(first, second)
        default: return false
        }
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
