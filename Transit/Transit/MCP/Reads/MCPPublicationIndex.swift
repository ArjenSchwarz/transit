import Foundation

nonisolated struct MCPPublicationRoot: Sendable {
    let id: String
    let deadline: ContinuousClock.Instant
    let encodedByteCount: Int
    let tokens: Set<String>
}

/// Validated once during preparation; the gate reads only bounded roots and scalars.
nonisolated struct MCPPublicationIndexDescriptor: Sendable {
    let roots: [String: MCPPublicationRoot]
    let entryCount: Int
    let encodedByteCount: Int
    let tokens: Set<String>

    init(roots: [MCPPublicationRoot]) throws {
        var mapping: [String: MCPPublicationRoot] = [:]
        var bytes = 0
        var tokens: Set<String> = []
        for root in roots {
            let (sum, overflow) = bytes.addingReportingOverflow(root.encodedByteCount)
            guard !root.id.isEmpty, root.encodedByteCount >= 0, !overflow,
                  mapping[root.id] == nil, tokens.isDisjoint(with: root.tokens) else {
                throw PublicationRejection.busy
            }
            mapping[root.id] = root
            bytes = sum
            tokens.formUnion(root.tokens)
        }
        self.roots = mapping
        self.entryCount = roots.count
        self.encodedByteCount = bytes
        self.tokens = tokens
    }
}

nonisolated protocol MCPPublicationIndex: AnyObject, Sendable {
    var descriptor: MCPPublicationIndexDescriptor { get }
}

nonisolated struct MCPPublicationStoreSnapshot: Sendable {
    let version: UInt64
    let tokenVersion: UInt64
    let index: any MCPPublicationIndex
    let allocatedTokenSets: [Set<String>]
}

nonisolated struct MCPPublicationAccounting: Equatable, Sendable {
    let visibleEntries: Int
    let visibleBytes: Int
    let pendingEntries: Int
    let pendingBytes: Int
}

/// Ownership and status are mutable only in the domain; indices remain immutable.
nonisolated final class MCPPublicationReservation: MCPPreparedPublication, @unchecked Sendable {
    enum Status { case pending, transferred, committed, discarded }
    let publicationStoreID: MCPPublicationStoreID
    let operationID: UUID
    let expectedVersion: UInt64
    let index: any MCPPublicationIndex
    let descriptor: MCPPublicationIndexDescriptor
    let chargeEntries: Int
    let chargeBytes: Int
    let newTokens: Set<String>
    let deadline: ContinuousClock.Instant
    let domain: MCPReadPublicationDomain
    var status = Status.pending

    init(storeID: MCPPublicationStoreID, operationID: UUID, expectedVersion: UInt64,
         index: any MCPPublicationIndex, descriptor: MCPPublicationIndexDescriptor,
         chargeEntries: Int, chargeBytes: Int, newTokens: Set<String>,
         deadline: ContinuousClock.Instant, domain: MCPReadPublicationDomain) {
        publicationStoreID = storeID
        self.operationID = operationID
        self.expectedVersion = expectedVersion
        self.index = index
        self.descriptor = descriptor
        self.chargeEntries = chargeEntries
        self.chargeBytes = chargeBytes
        self.newTokens = newTokens
        self.deadline = deadline
        self.domain = domain
    }

    func validateLocked(in domain: MCPReadPublicationDomain) -> PublicationRejection? {
        domain.validateLocked(self)
    }

    func commitLocked(in domain: MCPReadPublicationDomain) { domain.commitLocked(self) }
    func discardLocked(in domain: MCPReadPublicationDomain) { domain.discardLocked(self) }
}
