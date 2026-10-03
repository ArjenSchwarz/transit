#if os(macOS)
import Foundation

nonisolated enum MCPResultSourceKind: String, Sendable {
    case json, text, unreadable
}

nonisolated enum MCPResultEvidence: String, Sendable {
    case established, unestablished
}

/// Providers declare origin; a parse failure never guesses plain-text intent.
nonisolated enum MCPResultOrigin: Sendable {
    case generatedJSON
    case retainedJSON
    case plainText
}

nonisolated struct MCPResultSource: Sendable {
    let originalText: String
    let originalIsError: Bool?
    let document: MCPJSONDocument?
    let kind: MCPResultSourceKind
    let evidence: MCPResultEvidence
}

nonisolated enum MCPResultErrorCategory: String, Sendable {
    case invalidInput = "invalid_input"
    case notFound = "not_found"
    case ambiguousIdentity = "ambiguous_identity"
    case revisionConflict = "revision_conflict"
    case keyConflict = "key_conflict"
    case storageFailure = "storage_failure"
    case incoherentCapture = "incoherent_capture"
    case admissionBusy = "admission_busy"
    case deadlineExceeded = "deadline_exceeded"
    case retentionCapacity = "retention_capacity"
    case invalidCursor = "invalid_cursor"
    case expiredCursor = "expired_cursor"
    case serializationFailure = "serialization_failure"
    case outcomeUncertain = "outcome_uncertain"
    case unclassifiedHistorical = "unclassified_historical"
    case internalFailure = "internal_failure"
}

/// Explicit provider phase, distinct from any original payload code/message.
nonisolated struct MCPResultFailure: Sendable {
    let category: MCPResultErrorCategory
    let diagnostic: String?
}

nonisolated struct MCPProtectedRecoveryKey: Sendable, Equatable {
    let tool: String
    let idempotencyKey: String
}

nonisolated struct MCPBatchRecoveryItem: Sendable {
    let index: Int
    let itemId: String?
    let operation: String
    let originalKey: MCPProtectedRecoveryKey
    let targetTaskId: UUID?
}

/// Recovery evidence only: this type creates no durable key or acceptance state.
nonisolated enum MCPMutationRecoveryContext: Sendable {
    case protectedWrite(MCPProtectedRecoveryKey)
    case applicationBatch(items: [MCPBatchRecoveryItem])
    case unprotectedMaintenance(tool: String)
}

nonisolated enum MCPResultEntityType: String, Sendable {
    case task, project
}

/// JSON Pointer to an identity token in the provider's documented source shape.
nonisolated struct MCPResultEntityPosition: Sendable {
    let entityType: MCPResultEntityType
    let sourcePath: String
}

nonisolated struct MCPResultContext: Sendable {
    let tool: String
    let semanticFailure: MCPResultFailure?
    let mutationRecovery: MCPMutationRecoveryContext?
    let entityPositions: [MCPResultEntityPosition]
}

nonisolated enum MCPResultRecoveryDirection: String, Sendable {
    case followSource = "follow_source"
    case retryIdenticalRead = "retry_identical_read"
    case restartRead = "restart_read"
    case reconcileOriginalWrite = "reconcile_original_write"
    case reconcileMaintenance = "reconcile_maintenance"
}

nonisolated struct MCPResultRecovery: Sendable {
    let direction: MCPResultRecoveryDirection
    let mutation: MCPMutationRecoveryContext?
}

/// Metadata is an independent namespace, never inserted into original payloads.
nonisolated struct MCPResultMetadata: Sendable {
    let fields: [String: MCPJSONValue]
}
#endif
