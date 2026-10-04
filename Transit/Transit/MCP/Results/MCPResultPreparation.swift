#if os(macOS)
import Foundation

/// Value preparation only. This seam neither reserves capacity nor publishes roots.
/// Logical backing charges are not allocator capacity, RSS or a process peak bound.
nonisolated enum MCPResultPreparationError: Error, Sendable, Equatable {
    case notImplemented, invalidAccounting, arithmeticOverflow, retentionCapacity
}

nonisolated enum MCPResultRetentionStore: Sendable, CaseIterable {
    case ordinary, reusable
}

nonisolated struct MCPResultRetentionBudget: Sendable {
    static let limitBytes = 16 * 1_024 * 1_024
    let store: MCPResultRetentionStore
    /// Original capture/index plus separately retained legacy compatibility backing.
    /// Excludes text/documents/fragments/metadata already measured from prepared owners.
    let originalCaptureIndexBytes: Int
    /// Observations of this store only; the publication owner revalidates races later.
    let visibleBytes: Int
    let pendingBytes: Int
}

/// Factories own reference identities. Equal bytes never establish shared ownership.
nonisolated final class MCPResultPreparedMetadata: Sendable {
    let value: MCPResultMetadata
    fileprivate init(value: MCPResultMetadata) { self.value = value }
}

nonisolated final class MCPResultPreparedPage: Sendable {
    let source: MCPResultSource
    let presentation: MCPResultPresentation
    let fragment: MCPResultToolFragment
    let metadataOwner: MCPResultPreparedMetadata?

    fileprivate init(source: MCPResultSource, presentation: MCPResultPresentation,
                     fragment: MCPResultToolFragment, metadataOwner: MCPResultPreparedMetadata?) {
        self.source = source
        self.presentation = presentation
        self.fragment = fragment
        self.metadataOwner = metadataOwner
    }
}

nonisolated struct MCPResultPagePreparationRequest: Sendable {
    let text: String
    let isError: Bool?
    let origin: MCPResultOrigin
    let evidence: MCPResultEvidence
    let context: MCPResultContext
    let metadataOwner: MCPResultPreparedMetadata?
}

/// Normative retained components, measured once per actual immutable owner.
/// Tree root handles embedded in source/metadata are not charged again. Dynamic
/// case payloads include array handles/element slots, object member slots, decoded
/// UTF8 keys/strings and number lexemes. Presentation includes dynamic link/recovery
/// storage and strings. Distinct owners conservatively count despite hidden COW.
nonisolated struct MCPResultRetainedCharge: Sendable {
    let originalCaptureIndexBytes: Int
    let originalTextBytes: Int
    let sourceDocumentBytes: Int
    let sourceValueBytes: Int
    let presentationValueBytes: Int
    let fragmentBytes: Int
    let metadataDocumentBytes: Int
    let metadataValueBytes: Int
    /// Bundle array handle/every reference slot; each unique page's metadata
    /// pointer. Embedded source/presentation/fragment headers are charged above.
    let ownerReferenceBytes: Int
    let totalBytes: Int
    fileprivate init(originalCaptureIndexBytes: Int, originalTextBytes: Int,
                     sourceDocumentBytes: Int, sourceValueBytes: Int, presentationValueBytes: Int,
                     fragmentBytes: Int, metadataDocumentBytes: Int, metadataValueBytes: Int,
                     ownerReferenceBytes: Int, totalBytes: Int) {
        self.originalCaptureIndexBytes = originalCaptureIndexBytes
        self.originalTextBytes = originalTextBytes
        self.sourceDocumentBytes = sourceDocumentBytes
        self.sourceValueBytes = sourceValueBytes
        self.presentationValueBytes = presentationValueBytes
        self.fragmentBytes = fragmentBytes
        self.metadataDocumentBytes = metadataDocumentBytes
        self.metadataValueBytes = metadataValueBytes
        self.ownerReferenceBytes = ownerReferenceBytes
        self.totalBytes = totalBytes
    }
}

nonisolated struct MCPResultRetainedBundle: Sendable {
    let pages: [MCPResultPreparedPage]
    let charge: MCPResultRetainedCharge
    fileprivate init(pages: [MCPResultPreparedPage], charge: MCPResultRetainedCharge) {
        self.pages = pages
        self.charge = charge
    }
}

/// Synchronous immutable preparation. Original checkpoints are used but never retained.
nonisolated enum MCPResultPreparation {
    static func metadata(value: MCPResultMetadata) throws -> MCPResultPreparedMetadata {
        MCPResultPreparedMetadata(value: value)
    }

    static func page(request: MCPResultPagePreparationRequest,
                     checkpoint: @escaping @Sendable () throws -> Void = {}) throws -> MCPResultPreparedPage {
        try checkpoint()
        let source = try MCPResultAdapter.source(text: request.text, isError: request.isError,
            origin: request.origin, evidence: request.evidence, checkpoint: checkpoint)
        let presentation = try MCPResultAdapter.present(source, context: request.context, checkpoint: checkpoint)
        let fragment = try MCPResultEncoder.freeze(source: source, presentation: presentation,
                                                   metadata: request.metadataOwner?.value, checkpoint: checkpoint)
        try checkpoint()
        return MCPResultPreparedPage(source: source, presentation: presentation, fragment: fragment,
                                     metadataOwner: request.metadataOwner)
    }

    static func prepare(pages: [MCPResultPreparedPage], budget: MCPResultRetentionBudget,
                        checkpoint: @escaping @Sendable () throws -> Void = {}) throws -> MCPResultRetainedBundle {
        try checkpoint()
        let observed = [budget.originalCaptureIndexBytes, budget.visibleBytes, budget.pendingBytes]
        guard observed.allSatisfy({ $0 >= 0 }) else { throw MCPResultPreparationError.invalidAccounting }
        var ledger = MCPResultRetentionAccounting(checkpoint: checkpoint)
        try ledger.measure(pages)
        let total = try ledger.total(originalCaptureIndexBytes: budget.originalCaptureIndexBytes)
        let used = try MCPResultRetentionAccounting.add(
            MCPResultRetentionAccounting.add(budget.visibleBytes, budget.pendingBytes), total)
        guard used <= MCPResultRetentionBudget.limitBytes else { throw MCPResultPreparationError.retentionCapacity }
        try checkpoint()
        let charge = MCPResultRetainedCharge(originalCaptureIndexBytes: budget.originalCaptureIndexBytes,
            originalTextBytes: ledger.originalTextBytes, sourceDocumentBytes: ledger.sourceDocumentBytes,
            sourceValueBytes: ledger.sourceValueBytes, presentationValueBytes: ledger.presentationValueBytes,
            fragmentBytes: ledger.fragmentBytes, metadataDocumentBytes: ledger.metadataDocumentBytes,
            metadataValueBytes: ledger.metadataValueBytes, ownerReferenceBytes: ledger.ownerReferenceBytes,
            totalBytes: total)
        return MCPResultRetainedBundle(pages: pages, charge: charge)
    }
}
#endif
