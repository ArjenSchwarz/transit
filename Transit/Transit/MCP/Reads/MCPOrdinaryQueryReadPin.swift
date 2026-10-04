#if os(macOS)
import Foundation

/// Scalar proof of an exact immutable ordinary root and cursor, with its original deadline.
nonisolated struct MCPOrdinaryQueryReadPin: MCPPreparedPublication {
    let publicationStoreID: MCPPublicationStoreID
    let domain: MCPReadPublicationDomain
    let rootID: String
    let cursor: String
    let deadline: ContinuousClock.Instant

    func validateLocked(in domain: MCPReadPublicationDomain) -> PublicationRejection? {
        guard domain === self.domain else { return .busy }
        guard domain.currentInstantLocked < deadline,
              let index = domain.stores[publicationStoreID]?.index as? MCPTaskQuerySnapshotStore.Index,
              let root = index.descriptor.roots[rootID], root.deadline == deadline,
              root.tokens.contains(cursor), index.pages[cursor] != nil else { return .expired }
        return nil
    }

    func commitLocked(in domain: MCPReadPublicationDomain) {}
    func discardLocked(in domain: MCPReadPublicationDomain) {}
}

/// Coalesced read pins guard the optional single index mutation before any commit.
nonisolated struct MCPOrdinaryQueryGuardedPublication: MCPPreparedPublication {
    let publicationStoreID: MCPPublicationStoreID
    let domain: MCPReadPublicationDomain
    let pins: [MCPOrdinaryQueryReadPin]
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
