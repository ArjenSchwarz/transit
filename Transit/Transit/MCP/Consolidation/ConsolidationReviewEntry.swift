#if os(macOS)
import Foundation

/// Server-owned immutable proposal backing. The caller supplies only its opaque reference.
nonisolated struct ConsolidationReviewEntry: Sendable {
    enum Kind: String, Sendable { case apply, undo }
    let id: UUID
    let kind: Kind
    let originScopeId: String
    let revision: String
    let proposalBytes: Data
    let expiresAt: ContinuousClock.Instant

    /// Complete proposal backing plus fixed value/index handles and identity strings.
    var retainedByteCount: Int {
        proposalBytes.count + originScopeId.utf8.count + revision.utf8.count + kind.rawValue.utf8.count + 256
    }
}

extension MCPTaskQuerySnapshotStore {
    func prepareReview(_ entry: ConsolidationReviewEntry, bundle: MCPResultRetainedBundle,
                       operationID: UUID, deadline: ContinuousClock.Instant) throws -> MCPPublicationReservation {
        purgeExpired()
        guard now() < deadline, now() < entry.expiresAt else { throw expiryError() }
        let id = entry.id.uuidString
        guard MCPCursorFamily.classify(id) == .ordinary, !entry.originScopeId.isEmpty,
              entry.revision.range(of: "^p1:[0-9a-f]{64}$", options: .regularExpression)
                == entry.revision.startIndex..<entry.revision.endIndex,
              bundle.pages.count == 1, bundle.charge.originalCaptureIndexBytes == entry.retainedByteCount else {
            throw ConsolidationPlanningError.unavailableEvidence
        }
        guard bundle.charge.totalBytes <= maxBytes else { throw capacityError() }
        let base = try domain.snapshot(for: publicationStoreID)
        guard let original = base.index as? Index,
              base.allocatedTokenSets.allSatisfy({ !$0.contains(id) }) else { throw PublicationRejection.busy }
        let root = MCPPublicationRoot(id: id, deadline: entry.expiresAt,
            encodedByteCount: bundle.charge.totalBytes, tokens: [id])
        var reviews = original.reviews
        reviews[id] = entry
        var modern = original.modernRoots
        modern[id] = ModernRoot(bundle: bundle, rawMetadataBytes: 0)
        try Self.validateModernOwners(modern, operation: nil)
        let index = try Index(roots: Array(original.descriptor.roots.values) + [root],
            pages: original.pages, modernRoots: modern, reviews: reviews)
        do {
            return try domain.reserve(storeID: publicationStoreID, operationID: operationID,
                expectedVersion: base.version, expectedTokenVersion: base.tokenVersion, index: index,
                chargeEntries: 1, chargeBytes: bundle.charge.totalBytes, newTokens: root.tokens, deadline: deadline)
        } catch PublicationRejection.capacity { throw capacityError() } catch PublicationRejection.expired {
            throw expiryError()
        }
    }

    func review(id: UUID, revision: String, scope: String,
                kind: ConsolidationReviewEntry.Kind) throws -> ConsolidationReviewEntry {
        purgeExpired()
        let base = try domain.snapshot(for: publicationStoreID)
        let key = id.uuidString
        guard let index = base.index as? Index, let value = index.reviews[key],
              value.id == id, value.kind == kind, value.originScopeId == scope, value.revision == revision,
              let root = index.descriptor.roots[key], root.deadline == value.expiresAt else {
            throw ConsolidationPlanningError.unavailableEvidence
        }
        // Review roots have no page cursor. Validate their exact immutable identity under
        // the existing domain gate without changing legacy page-pin requirements.
        let valid = domain.withLock {
            guard domain.currentInstantLocked < root.deadline,
                  let current = domain.stores[publicationStoreID]?.index as? Index,
                  let retained = current.reviews[key], let currentRoot = current.descriptor.roots[key] else {
                return false
            }
            return currentRoot.deadline == root.deadline && currentRoot.tokens.contains(key)
                && retained.id == id && retained.revision == revision && retained.originScopeId == scope
                && retained.kind == kind && retained.expiresAt == root.deadline
        }
        guard valid else {
            throw ConsolidationPlanningError.unavailableEvidence
        }
        return value
    }
}
#endif
