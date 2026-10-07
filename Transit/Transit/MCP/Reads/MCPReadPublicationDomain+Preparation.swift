import Foundation

extension MCPReadPublicationDomain {
    // swiftlint:disable:next function_parameter_count
    nonisolated func reserve(
        storeID: MCPPublicationStoreID, operationID: UUID, expectedVersion: UInt64,
        expectedTokenVersion: UInt64, index: any MCPPublicationIndex, chargeEntries: Int,
        chargeBytes: Int, newTokens: Set<String>, deadline: ContinuousClock.Instant
    ) throws -> MCPPublicationReservation {
        let base = try snapshot(for: storeID)
        let descriptor = index.descriptor
        guard base.version == expectedVersion, base.tokenVersion == expectedTokenVersion,
              chargeEntries >= 0, chargeBytes >= 0,
              descriptor.entryCount <= 8,
              descriptor.entryCount - base.index.descriptor.entryCount == chargeEntries,
              descriptor.encodedByteCount - base.index.descriptor.encodedByteCount == chargeBytes,
              descriptor.tokens.subtracting(base.index.descriptor.tokens) == newTokens,
              base.allocatedTokenSets.allSatisfy({ newTokens.isDisjoint(with: $0) }) else {
            throw PublicationRejection.busy
        }
        try validateExtension(descriptor, of: base.index.descriptor)
        let reservation = MCPPublicationReservation(storeID: storeID, operationID: operationID,
            expectedVersion: expectedVersion, index: index, descriptor: descriptor,
            chargeEntries: chargeEntries, chargeBytes: chargeBytes, newTokens: newTokens,
            deadline: deadline, domain: self)
        try withLock {
            guard let store = stores[storeID], store.version == expectedVersion,
                  tokenVersion == expectedTokenVersion, store.pending[operationID] == nil else {
                throw PublicationRejection.busy
            }
            guard store.pending.count < 8,
                  chargeEntries <= store.maxEntries - store.descriptor.entryCount - store.pendingEntries,
                  chargeBytes <= store.maxBytes - store.descriptor.encodedByteCount - store.pendingBytes else {
                throw PublicationRejection.capacity
            }
            let instant = currentInstantLocked
            guard instant < deadline, descriptor.roots.values.allSatisfy({ instant < $0.deadline }) else {
                throw PublicationRejection.expired
            }
            store.pending[operationID] = reservation
            store.pendingEntries += chargeEntries
            store.pendingBytes += chargeBytes
            tokenVersion &+= 1
        }
        return reservation
    }

    /// Sibling allocations advance the global token version, so transfer pins a fresh
    /// allocation snapshot rather than requiring each child's historic token version.
    nonisolated func transfer(
        _ children: [MCPPublicationReservation], aggregateIndex: any MCPPublicationIndex, operationID: UUID
    ) throws -> MCPPublicationReservation {
        guard let first = children.first, children.count <= 8,
              Set(children.map(\.operationID)).count == children.count,
              children.allSatisfy({ $0.domain === self && $0.publicationStoreID == first.publicationStoreID
                  && $0.expectedVersion == first.expectedVersion }) else { throw PublicationRejection.busy }
        let base = try snapshot(for: first.publicationStoreID)
        guard base.version == first.expectedVersion else { throw PublicationRejection.busy }
        let descriptor = aggregateIndex.descriptor
        let bytes = try checkedSum(children.map(\.chargeBytes))
        let entries = try checkedSum(children.map(\.chargeEntries))
        var tokens: Set<String> = []
        for child in children {
            guard tokens.isDisjoint(with: child.newTokens) else { throw PublicationRejection.busy }
            tokens.formUnion(child.newTokens)
        }
        guard descriptor.entryCount <= 8,
              descriptor.entryCount - base.index.descriptor.entryCount == entries,
              descriptor.encodedByteCount - base.index.descriptor.encodedByteCount == bytes,
              descriptor.tokens == base.index.descriptor.tokens.union(tokens) else { throw PublicationRejection.busy }
        try validateAggregate(descriptor, children: children, base: base.index.descriptor)
        let aggregate = MCPPublicationReservation(storeID: first.publicationStoreID, operationID: operationID,
            expectedVersion: base.version, index: aggregateIndex, descriptor: descriptor,
            chargeEntries: entries, chargeBytes: bytes, newTokens: tokens,
            deadline: children.map(\.deadline).min() ?? first.deadline, domain: self)
        try withLock {
            guard let store = stores[first.publicationStoreID], store.version == base.version,
                  tokenVersion == base.tokenVersion,
                  store.pending[operationID] == nil,
                  children.allSatisfy({ $0.status == .pending && store.pending[$0.operationID] === $0 }) else {
                throw PublicationRejection.busy
            }
            let instant = currentInstantLocked
            guard instant < aggregate.deadline,
                  descriptor.roots.values.allSatisfy({ instant < $0.deadline }) else {
                throw PublicationRejection.expired
            }
            // The summed charge remains unchanged throughout this ownership move.
            for child in children {
                retireLocked(child)
                store.pending.removeValue(forKey: child.operationID)
                child.status = .transferred
            }
            store.pending[operationID] = aggregate
            tokenVersion &+= 1
        }
        return aggregate
    }

    nonisolated func retire(
        storeID: MCPPublicationStoreID, expectedVersion: UInt64, replacementIndex: any MCPPublicationIndex
    ) throws {
        let base = try snapshot(for: storeID)
        let old = base.index.descriptor
        let replacement = replacementIndex.descriptor
        guard base.version == expectedVersion,
              replacement.roots.allSatisfy({ key, root in
                  guard let original = old.roots[key] else { return false }
                  return root.deadline == original.deadline && root.encodedByteCount == original.encodedByteCount
                      && root.tokens == original.tokens
              }) else { throw PublicationRejection.busy }
        try withLock {
            guard let store = stores[storeID], store.version == expectedVersion else { throw PublicationRejection.busy }
            retireLocked(store.index)
            store.index = replacementIndex
            store.descriptor = replacement
            store.version &+= 1
            tokenVersion &+= 1
        }
    }

    private nonisolated func checkedSum(_ values: [Int]) throws -> Int {
        try values.reduce(0) { result, value in
            let (sum, overflow) = result.addingReportingOverflow(value)
            guard value >= 0, !overflow else { throw PublicationRejection.busy }
            return sum
        }
    }

    private nonisolated func validateExtension(
        _ candidate: MCPPublicationIndexDescriptor, of base: MCPPublicationIndexDescriptor
    ) throws {
        for (key, original) in base.roots {
            guard let root = candidate.roots[key], root.deadline == original.deadline,
                  root.encodedByteCount >= original.encodedByteCount,
                  original.tokens.isSubset(of: root.tokens) else { throw PublicationRejection.busy }
        }
    }

    private nonisolated func validateAggregate(
        _ aggregate: MCPPublicationIndexDescriptor,
        children: [MCPPublicationReservation], base: MCPPublicationIndexDescriptor
    ) throws {
        try validateExtension(aggregate, of: base)
        var roots = base.roots
        for child in children {
            for (key, root) in child.descriptor.roots {
                if let original = base.roots[key] {
                    guard let combined = roots[key] else { throw PublicationRejection.busy }
                    roots[key] = MCPPublicationRoot(id: key, deadline: min(combined.deadline, root.deadline),
                        encodedByteCount: try checkedSum([combined.encodedByteCount,
                            root.encodedByteCount - original.encodedByteCount]),
                        tokens: combined.tokens.union(root.tokens))
                } else {
                    guard roots[key] == nil else { throw PublicationRejection.busy }
                    roots[key] = root
                }
            }
        }
        guard roots.count == aggregate.entryCount, roots.allSatisfy({ key, root in
            guard let result = aggregate.roots[key] else { return false }
            return result.deadline == root.deadline && result.encodedByteCount == root.encodedByteCount
                && result.tokens == root.tokens
        }) else { throw PublicationRejection.busy }
    }
}
