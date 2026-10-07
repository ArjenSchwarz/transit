#if os(macOS)
import Foundation

extension MCPTaskQuerySnapshotStore {
    nonisolated struct ModernRoot: Sendable {
        let bundle: MCPResultRetainedBundle
        /// Raw compatibility metadata is excluded from bundle.originalCaptureIndexBytes.
        let rawMetadataBytes: Int
    }

    // Retains all page owners, including the first, before visibility. Bundle base must exclude
    // raw metadata supplied here; its separately retained backing is added exactly once per root.
    // swiftlint:disable function_parameter_count cyclomatic_complexity
    func prepare(preparedBundle: MCPResultRetainedBundle, cursors: [String],
                 deadline: ContinuousClock.Instant, operationID: UUID, metadataBytes: Data?,
                 policy: MCPReadPolicy?, operation: MCPReadOperation? = nil) throws -> MCPPublicationReservation? {
        try Self.check(operation)
        if let operation, operation.id != operationID { throw PublicationRejection.busy }
        purgeExpired()
        guard now() < deadline else { throw expiryError() }
        let owners = preparedBundle.pages
        guard !owners.isEmpty, cursors.count == owners.count - 1,
              Set(cursors).count == cursors.count,
              cursors.allSatisfy({ MCPCursorFamily.classify($0) == .ordinary }) else {
            throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Could not publish query pages")
        }
        let bytes: Int
        do {
            bytes = try Self.add(preparedBundle.charge.totalBytes, metadataBytes?.count ?? 0)
        } catch PublicationRejection.capacity { throw capacityError() }
        guard bytes <= maxBytes else { throw capacityError() }
        guard owners.count > 1 else { return nil }
        let base = try domain.snapshot(for: publicationStoreID)
        guard let original = base.index as? Index else { throw PublicationRejection.busy }
        let tokens = Set(cursors)
        guard base.allocatedTokenSets.allSatisfy({ tokens.isDisjoint(with: $0) }) else {
            throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Could not publish query pages")
        }
        let id = UUID().uuidString
        let root = MCPPublicationRoot(id: id, deadline: deadline, encodedByteCount: bytes,
                                      tokens: tokens.union([id]))
        var modernRoots = original.modernRoots
        modernRoots[id] = ModernRoot(bundle: preparedBundle, rawMetadataBytes: metadataBytes?.count ?? 0)
        try Self.validateModernOwners(modernRoots, operation: operation)
        var mapping = original.pages
        for (token, owner) in zip(cursors, owners.dropFirst()) {
            try Self.check(operation)
            mapping[token] = MCPRetainedQueryPage(text: owner.source.originalText,
                metadataBytes: metadataBytes, policy: policy, preparedResultPage: owner)
        }
        let candidate = try Index(roots: Array(original.descriptor.roots.values) + [root],
                                  pages: mapping, modernRoots: modernRoots, reviews: original.reviews)
        try Self.check(operation)
        do {
            return try domain.reserve(storeID: publicationStoreID, operationID: operationID,
                expectedVersion: base.version, expectedTokenVersion: base.tokenVersion, index: candidate,
                chargeEntries: 1, chargeBytes: bytes, newTokens: root.tokens, deadline: deadline)
        } catch PublicationRejection.capacity { throw capacityError() } catch PublicationRejection.expired {
            throw expiryError()
        }
    }
    // swiftlint:enable function_parameter_count cyclomatic_complexity

    nonisolated func prepareAggregate(_ publications: [any MCPPreparedPublication],
                                      in domain: MCPReadPublicationDomain,
                                      operation: MCPReadOperation) throws -> any MCPPreparedPublication {
        try prepareAggregate(publications, in: domain, checking: operation)
    }

    // The protocol compatibility path still validates fixed additive root ownership; only the
    // operation-aware path remeasures backing with the caller's original checkpoint.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    nonisolated func prepareAggregate(_ publications: [any MCPPreparedPublication],
                                      in domain: MCPReadPublicationDomain,
                                      checking operation: MCPReadOperation?) throws -> any MCPPreparedPublication {
        try Self.check(operation)
        guard domain === self.domain, !publications.isEmpty, publications.count <= 8 else {
            throw PublicationRejection.busy
        }
        let base = try domain.snapshot(for: publicationStoreID)
        guard let index = base.index as? Index else { throw PublicationRejection.busy }
        var roots = index.descriptor.roots
        var pages = index.pages
        var modernRoots = index.modernRoots
        var reviews = index.reviews
        var children: [MCPPublicationReservation] = []
        var pins: [MCPOrdinaryQueryReadPin] = []
        for publication in publications {
            try Self.check(operation)
            if let pin = publication as? MCPOrdinaryQueryReadPin {
                guard pin.domain === domain, pin.publicationStoreID == publicationStoreID else {
                    throw PublicationRejection.busy
                }
                pins.append(pin)
                continue
            }
            guard let child = publication as? MCPPublicationReservation,
                  child.publicationStoreID == publicationStoreID, child.domain === domain,
                  child.expectedVersion == base.version,
                  let candidate = child.index as? Index else { throw PublicationRejection.busy }
            children.append(child)
            for (key, root) in candidate.descriptor.roots where index.descriptor.roots[key] == nil {
                try Self.check(operation)
                guard roots[key] == nil else { throw PublicationRejection.busy }
                roots[key] = root
                if let modern = candidate.modernRoots[key] { modernRoots[key] = modern }
                if let review = candidate.reviews[key] { reviews[key] = review }
            }
            for (token, page) in candidate.pages where index.pages[token] == nil {
                try Self.check(operation)
                guard pages[token] == nil else { throw PublicationRejection.busy }
                pages[token] = page
            }
        }
        if children.isEmpty {
            return MCPOrdinaryQueryGuardedPublication(publicationStoreID: publicationStoreID,
                domain: domain, pins: pins, mutation: nil)
        }
        try Self.validateModernOwners(modernRoots, operation: operation)
        for (id, modern) in modernRoots {
            try Self.check(operation)
            let bytes: Int
            if let operation {
                let measured = try MCPResultPreparation.prepare(pages: modern.bundle.pages,
                    budget: MCPResultRetentionBudget(store: .ordinary,
                        originalCaptureIndexBytes: modern.bundle.charge.originalCaptureIndexBytes,
                        visibleBytes: 0, pendingBytes: 0), checkpoint: {
                            try Self.check(operation)
                        })
                bytes = try Self.add(measured.charge.totalBytes, modern.rawMetadataBytes)
            } else {
                bytes = try Self.add(modern.bundle.charge.totalBytes, modern.rawMetadataBytes)
            }
            guard roots[id]?.encodedByteCount == bytes else { throw PublicationRejection.busy }
        }
        let candidate = try Index(roots: Array(roots.values), pages: pages, modernRoots: modernRoots, reviews: reviews)
        try Self.check(operation)
        if let operation {
            if children.count == 1, let child = children.first {
                guard child.operationID == operation.id else { throw PublicationRejection.busy }
                if pins.isEmpty { return child }
                return MCPOrdinaryQueryGuardedPublication(
                    publicationStoreID: publicationStoreID, domain: domain, pins: pins, mutation: child)
            }
            // Transfer cannot replace a live child slot with the same UUID. An aggregate operation
            // owns a distinct ID; children keep their own unique IDs until the gapless transfer.
            guard children.allSatisfy({ $0.operationID != operation.id }) else { throw PublicationRejection.busy }
        }
        let mutation = try domain.transfer(children, aggregateIndex: candidate, operationID: operation?.id ?? UUID())
        if pins.isEmpty { return mutation }
        return MCPOrdinaryQueryGuardedPublication(
            publicationStoreID: publicationStoreID, domain: domain, pins: pins, mutation: mutation)
    }

    /// Sharing inside one bundle is intentional. Different roots must own disjoint new page and
    /// metadata allocations, or fixed root charges/retirement would double-charge a shared owner.
    nonisolated static func validateModernOwners(_ roots: [String: ModernRoot],
                                                 operation: MCPReadOperation?) throws {
        var previous: Set<ObjectIdentifier> = []
        for root in roots.values {
            try check(operation)
            var owners: Set<ObjectIdentifier> = []
            for page in root.bundle.pages {
                try check(operation)
                owners.insert(ObjectIdentifier(page))
                if let metadata = page.metadataOwner { owners.insert(ObjectIdentifier(metadata)) }
            }
            guard previous.isDisjoint(with: owners) else { throw PublicationRejection.busy }
            previous.formUnion(owners)
        }
    }

    nonisolated private static func check(_ operation: MCPReadOperation?) throws {
        if let operation, !operation.shouldContinue() { throw CancellationError() }
    }

    nonisolated private static func add(_ left: Int, _ right: Int) throws -> Int {
        let (total, overflow) = left.addingReportingOverflow(right)
        guard left >= 0, right >= 0, !overflow else { throw PublicationRejection.capacity }
        return total
    }
}
#endif
