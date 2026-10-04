#if os(macOS)
import Foundation

/// Scalar proof of the exact root pinned during value lookup, including its original lifetime.
nonisolated struct MCPReusableSnapshotReadPin: MCPPreparedPublication {
    let publicationStoreID: MCPPublicationStoreID
    let domain: MCPReadPublicationDomain
    let snapshotID: String
    let identity: UUID
    let deadline: ContinuousClock.Instant
    let cursor: String?

    func validateLocked(in domain: MCPReadPublicationDomain) -> PublicationRejection? {
        guard domain === self.domain else { return .busy }
        guard domain.currentInstantLocked < deadline,
              let index = domain.stores[publicationStoreID]?.index as? MCPReusableSnapshotIndex,
              let entry = index.entries[snapshotID], entry.identity == identity,
              entry.bundle.root.capture.retentionDeadline == deadline else { return .expired }
        if let cursor {
            guard index.pageRoots[cursor] == snapshotID, entry.pages[cursor] != nil else { return .expired }
        }
        return nil
    }

    func commitLocked(in domain: MCPReadPublicationDomain) {}
    func discardLocked(in domain: MCPReadPublicationDomain) {}
}

/// One store participant: validate read guards before the optional single mutation swap.
nonisolated struct MCPReusableSnapshotGuardedPublication: MCPPreparedPublication {
    let publicationStoreID: MCPPublicationStoreID
    let domain: MCPReadPublicationDomain
    let pins: [MCPReusableSnapshotReadPin]
    let mutation: MCPPublicationReservation?

    func validateLocked(in domain: MCPReadPublicationDomain) -> PublicationRejection? {
        guard domain === self.domain, pins.count <= 8,
              mutation.map({ $0.publicationStoreID == publicationStoreID && $0.domain === domain }) ?? true else {
            return .busy
        }
        for pin in pins {
            guard pin.publicationStoreID == publicationStoreID else { return .busy }
            if let rejection = pin.validateLocked(in: domain) { return rejection }
        }
        return mutation?.validateLocked(in: domain)
    }

    func commitLocked(in domain: MCPReadPublicationDomain) { mutation?.commitLocked(in: domain) }
    func discardLocked(in domain: MCPReadPublicationDomain) { mutation?.discardLocked(in: domain) }
}
#endif
