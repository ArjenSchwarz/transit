#if os(macOS)
import Foundation

extension MCPReusableSnapshotStore {
    nonisolated func preparedResultBudget(originalCaptureIndexBytes: Int, replacingSnapshotID: String? = nil,
                                          operation: MCPReadOperation) throws -> MCPResultRetentionBudget {
        let base = try preparedObservation(operation)
        return try budget(base, legacyBytes: originalCaptureIndexBytes, replacing: replacingSnapshotID)
    }

    nonisolated func reservePreparedCreate(bundle: EncodedViewBundle, preparedResults: MCPResultRetainedBundle,
                                           operation: MCPReadOperation, publicationDeadline: ContinuousClock.Instant)
                                           throws -> RetentionReservation {
        try MCPPortfolioReadEncoding.check(operation)
        guard case .completePortfolio = bundle.root.capture.completeness,
              bundle.root.capture.captureScope != .selectedQuery, case .initial = bundle.root.initialRequest,
              bundle.root.capture.createdAt.duration(to: bundle.root.capture.retentionDeadline) == .seconds(300),
              !bundle.root.capture.metadata.snapshotId.isEmpty,
              preparedResults.pages.count == bundle.pages.count + 1,
              let firstOwner = preparedResults.pages.first else {
            throw MCPReusableSnapshotError.incompatible
        }
        guard bundle.root.preparedResultPage == nil || bundle.root.preparedResultPage === firstOwner else {
            throw MCPReusableSnapshotError.incompatible
        }
        let mapping = try pageMapping(pages: bundle.pages, cursors: bundle.cursors)
        try validateOwners(preparedResults.pages, root: bundle.root,
                           bytes: [bundle.root.firstPage] + bundle.pages, operation: operation)
        let root = RetainedView(capture: bundle.root.capture, frozenMetadataBytes: bundle.root.frozenMetadataBytes,
            window: bundle.root.window, initialRequest: bundle.root.initialRequest,
            firstPage: bundle.root.firstPage, preparedResultPage: firstOwner)
        let normalized = EncodedViewBundle(root: root, pages: bundle.pages, cursors: bundle.cursors,
            encodedCaptureByteCount: bundle.encodedCaptureByteCount, lifetimeProbe: bundle.lifetimeProbe)
        let base = try preparedObservation(operation)
        let id = bundle.root.capture.metadata.snapshotId
        guard base.index.entries[id] == nil else { throw PublicationRejection.busy }
        let legacy = try legacyBytes(normalized, pages: mapping, operation: operation)
        let measured = try measure(preparedResults.pages, budget: budget(base, legacyBytes: legacy, replacing: nil),
                                   operation: operation)
        guard measured.charge.totalBytes == preparedResults.charge.totalBytes else {
            throw MCPReusableSnapshotError.incompatible
        }
        let owners = Dictionary(uniqueKeysWithValues: zip(bundle.cursors, preparedResults.pages.dropFirst()))
        let entry = MCPReusableSnapshotEntry(bundle: normalized, pages: mapping,
            preparedResultPages: owners, preparedResultBundle: measured)
        try rejectForeignOwners(entry, rootID: id, observation: base, operation: operation)
        var entries = base.index.entries
        entries[id] = entry
        let candidate = try MCPReusableSnapshotIndex(entries: entries,
            checkpoint: { try MCPPortfolioReadEncoding.check(operation) })
        try MCPPortfolioReadEncoding.check(operation)
        let deadline = min(publicationDeadline, try MCPPortfolioReadEncoding.publicationDeadline(operation))
        return try reserve(base: base.snapshot, candidate: candidate, deadline: deadline)
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated func reservePreparedAppend(snapshotID: String, pages: [Data], cursors: [String],
                                           preparedPages: [MCPResultPreparedPage],
                                           operation: MCPReadOperation,
                                           publicationDeadline: ContinuousClock.Instant) throws
        -> RetentionReservation {
        let base = try preparedObservation(operation)
        guard let original = base.index.entries[snapshotID] else { throw MCPReusableSnapshotError.invalidSnapshot }
        guard let retained = original.preparedResultBundle, preparedPages.count == pages.count + 1 else {
            throw MCPReusableSnapshotError.incompatible
        }
        let additions = try pageMapping(pages: pages, cursors: cursors)
        // The first projection response is retained even when it has no continuation.
        try validateOwners(preparedPages, root: original.bundle.root, bytes: nil, operation: operation)
        for (page, bytes) in zip(preparedPages.dropFirst(), pages) {
            guard try cooperativelyEqual(page.source.originalText.utf8, bytes, operation: operation) else {
                throw MCPReusableSnapshotError.incompatible
            }
        }
        var mapping = original.pages
        var owners = original.preparedResultPages
        for (cursor, bytes) in additions {
            try MCPPortfolioReadEncoding.check(operation)
            guard mapping[cursor] == nil else { throw PublicationRejection.busy }
            mapping[cursor] = bytes
        }
        for (cursor, owner) in zip(cursors, preparedPages.dropFirst()) { owners[cursor] = owner }
        let union = try ownerUnion(retained.pages + preparedPages, operation: operation)
        let legacy = try legacyBytes(original.bundle, pages: mapping, operation: operation)
        let measured = try measure(union, budget: budget(base, legacyBytes: legacy, replacing: snapshotID),
                                   operation: operation)
        let entry = MCPReusableSnapshotEntry(identity: original.identity, bundle: original.bundle, pages: mapping,
            preparedResultPages: owners, preparedResultBundle: measured)
        try rejectForeignOwners(entry, rootID: snapshotID, observation: base, operation: operation)
        var entries = base.index.entries
        entries[snapshotID] = entry
        let candidate = try MCPReusableSnapshotIndex(entries: entries,
            checkpoint: { try MCPPortfolioReadEncoding.check(operation) })
        try MCPPortfolioReadEncoding.check(operation)
        let deadline = min(publicationDeadline, try MCPPortfolioReadEncoding.publicationDeadline(operation))
        return try reserve(base: base.snapshot, candidate: candidate, deadline: deadline)
    }

    // swiftlint:disable large_tuple
    nonisolated func preparedResultView(for snapshotID: String, now: ContinuousClock.Instant,
                                        testingAfterPin: (() throws -> Void)? = nil) throws
        -> (root: RetainedView, firstPage: MCPResultPreparedPage, pin: MCPReusableSnapshotReadPin) {
        let pinned = try preparedRetainedView(for: snapshotID, now: now, testingAfterPin: testingAfterPin)
        guard let owner = pinned.root.preparedResultPage else { throw MCPReusableSnapshotError.incompatible }
        return (pinned.root, owner, pinned.pin)
    }

    nonisolated func preparedResultPage(for cursor: String, now: ContinuousClock.Instant,
                                        testingAfterPin: (() throws -> Void)? = nil) throws
        -> (page: RetainedPage, preparedPage: MCPResultPreparedPage, pin: MCPReusableSnapshotReadPin) {
        guard MCPCursorFamily.classify(cursor) == .reusable else { throw MCPReusableSnapshotError.invalidCursor }
        let base = try liveSnapshot(now: now)
        guard let index = base.index as? MCPReusableSnapshotIndex, let id = index.pageRoots[cursor],
              let entry = index.entries[id], let bytes = entry.pages[cursor] else {
            throw MCPReusableSnapshotError.invalidCursor
        }
        guard let owner = entry.preparedResultPages[cursor] else { throw MCPReusableSnapshotError.incompatible }
        let pin = MCPReusableSnapshotReadPin(publicationStoreID: publicationStoreID, domain: domain,
            snapshotID: id, identity: entry.identity,
            deadline: entry.bundle.root.capture.retentionDeadline, cursor: cursor)
        try testingAfterPin?()
        guard domain.withLock({ pin.validateLocked(in: domain) == nil }), now < pin.deadline else {
            throw MCPReusableSnapshotError.invalidCursor
        }
        return (RetainedPage(root: entry.bundle.root, encodedPage: bytes, preparedResultPage: owner), owner, pin)
    }
    // swiftlint:enable large_tuple
}

extension MCPReusableSnapshotStore {
    /// Private preparation under the original admitted operation, before shared ownership transfer.
    nonisolated func prepareAggregate(_ publications: [any MCPPreparedPublication], in domain: MCPReadPublicationDomain,
                                      operation: MCPReadOperation) throws -> any MCPPreparedPublication {
        try MCPPortfolioReadEncoding.check(operation)
        guard domain === self.domain else { throw PublicationRejection.busy }
        let (children, pins) = try publicationParts(publications, in: domain)
        guard children.count > 1 else { return try prepareAggregate(publications, in: domain) }
        let base = try preparedObservation(operation)
        var existingIdentities: Set<ObjectIdentifier> = []
        for entry in base.index.entries.values {
            existingIdentities.formUnion(try ownerIdentities(entry, operation: operation))
        }
        var newIdentities: Set<ObjectIdentifier> = []
        var entries = base.index.entries
        for child in children {
            try MCPPortfolioReadEncoding.check(operation)
            guard child.expectedVersion == base.snapshot.version,
                  let candidate = child.index as? MCPReusableSnapshotIndex else { throw PublicationRejection.busy }
            let introduced = try introducedOwners(candidate, excluding: existingIdentities, operation: operation)
            guard introduced.isDisjoint(with: newIdentities) else { throw PublicationRejection.busy }
            newIdentities.formUnion(introduced)
            entries = try mergeCandidate(candidate, original: base.index, combined: entries, operation: operation)
        }
        let candidate = try MCPReusableSnapshotIndex(entries: entries,
            checkpoint: { try MCPPortfolioReadEncoding.check(operation) })
        try MCPPortfolioReadEncoding.check(operation)
        let mutation = try domain.transfer(children, aggregateIndex: candidate, operationID: UUID())
        if pins.isEmpty { return mutation }
        return MCPReusableSnapshotGuardedPublication(publicationStoreID: publicationStoreID,
            domain: domain, pins: pins, mutation: mutation)
    }
}

private extension MCPReusableSnapshotStore {
    nonisolated func mergeCandidate(_ candidate: MCPReusableSnapshotIndex, original: MCPReusableSnapshotIndex,
                                    combined: [String: MCPReusableSnapshotEntry], operation: MCPReadOperation) throws
        -> [String: MCPReusableSnapshotEntry] {
        var entries = combined
        for (id, entry) in candidate.entries {
            try MCPPortfolioReadEncoding.check(operation)
            guard let initial = original.entries[id] else {
                guard entries[id] == nil else { throw PublicationRejection.busy }
                entries[id] = entry
                continue
            }
            guard let current = entries[id], entry.identity == initial.identity else { throw PublicationRejection.busy }
            entries[id] = try mergedPreparedEntry(original: initial, current: current,
                                                  addition: entry, operation: operation)
        }
        return entries
    }

    nonisolated func introducedOwners(_ index: MCPReusableSnapshotIndex, excluding existing: Set<ObjectIdentifier>,
                                      operation: MCPReadOperation) throws -> Set<ObjectIdentifier> {
        var introduced: Set<ObjectIdentifier> = []
        for entry in index.entries.values {
            introduced.formUnion(try ownerIdentities(entry, operation: operation))
        }
        introduced.subtract(existing)
        return introduced
    }

    nonisolated func mergedPreparedEntry(original: MCPReusableSnapshotEntry, current: MCPReusableSnapshotEntry,
                                         addition: MCPReusableSnapshotEntry, operation: MCPReadOperation) throws
        -> MCPReusableSnapshotEntry {
        var pages = current.pages
        var owners = current.preparedResultPages
        for (cursor, bytes) in addition.pages where original.pages[cursor] == nil {
            try MCPPortfolioReadEncoding.check(operation)
            guard pages[cursor] == nil else { throw PublicationRejection.busy }
            pages[cursor] = bytes
            owners[cursor] = addition.preparedResultPages[cursor]
        }
        let combined = try ownerUnion((current.preparedResultBundle?.pages ?? [])
            + (addition.preparedResultBundle?.pages ?? []), operation: operation)
        let prepared: MCPResultRetainedBundle?
        if current.preparedResultBundle != nil || addition.preparedResultBundle != nil {
            guard current.preparedResultBundle != nil, addition.preparedResultBundle != nil else {
                throw MCPReusableSnapshotError.incompatible
            }
            let legacy = try legacyBytes(original.bundle, pages: pages, operation: operation)
            // Children already own exact additive pending deltas; transfer revalidates their sum.
            prepared = try measure(combined, budget: MCPResultRetentionBudget(store: .reusable,
                originalCaptureIndexBytes: legacy, visibleBytes: 0, pendingBytes: 0), operation: operation)
        } else { prepared = nil }
        return MCPReusableSnapshotEntry(identity: original.identity, bundle: original.bundle,
            pages: pages, preparedResultPages: owners, preparedResultBundle: prepared)
    }

    nonisolated struct PreparedObservation {
        let snapshot: MCPPublicationStoreSnapshot
        let index: MCPReusableSnapshotIndex
        let pendingBytes: Int
        let pending: [MCPReusableSnapshotIndex]
    }

    nonisolated func preparedObservation(_ operation: MCPReadOperation) throws -> PreparedObservation {
        try MCPPortfolioReadEncoding.check(operation)
        let snapshot = try liveSnapshot()
        guard let index = snapshot.index as? MCPReusableSnapshotIndex else { throw PublicationRejection.busy }
        let observed = try domain.withLock {
            guard let state = domain.stores[publicationStoreID], state.version == snapshot.version,
                  domain.tokenVersion == snapshot.tokenVersion else { throw PublicationRejection.busy }
            return (state.pendingBytes, state.pending.values.compactMap { $0.index as? MCPReusableSnapshotIndex })
        }
        try MCPPortfolioReadEncoding.check(operation)
        return PreparedObservation(snapshot: snapshot, index: index, pendingBytes: observed.0, pending: observed.1)
    }

    nonisolated func budget(_ observed: PreparedObservation, legacyBytes: Int, replacing id: String?) throws
        -> MCPResultRetentionBudget {
        var visible = observed.index.descriptor.encodedByteCount
        if let id {
            guard let root = observed.index.descriptor.roots[id] else { throw MCPReusableSnapshotError.invalidSnapshot }
            visible = try checkedDifference(visible, root.encodedByteCount)
        }
        return MCPResultRetentionBudget(store: .reusable, originalCaptureIndexBytes: legacyBytes,
                                        visibleBytes: visible, pendingBytes: observed.pendingBytes)
    }

    nonisolated func checkedDifference(_ total: Int, _ original: Int) throws -> Int {
        guard total >= 0, original >= 0 else { throw MCPResultPreparationError.invalidAccounting }
        let (difference, overflow) = total.subtractingReportingOverflow(original)
        guard !overflow, difference >= 0 else { throw MCPResultPreparationError.invalidAccounting }
        return difference
    }

    nonisolated func legacyBytes(_ bundle: EncodedViewBundle, pages: [String: Data],
                                 operation: MCPReadOperation) throws -> Int {
        var total = try MCPResultRetentionAccounting.add(bundle.encodedCaptureByteCount, bundle.root.firstPage.count)
        for bytes in pages.values {
            try MCPPortfolioReadEncoding.check(operation)
            total = try MCPResultRetentionAccounting.add(total, bytes.count)
        }
        return total
    }

    nonisolated func validateOwners(_ owners: [MCPResultPreparedPage], root: RetainedView, bytes: [Data]?,
                                    operation: MCPReadOperation) throws {
        let expected = [Data("{\"me.nore.ig.transit/read\":".utf8), root.frozenMetadataBytes, Data("}".utf8)].joined()
        for (position, owner) in owners.enumerated() {
            try MCPPortfolioReadEncoding.check(operation)
            guard let metadata = owner.metadataOwner,
                  try cooperativelyEqual(metadata.value.document.originalUTF8, expected, operation: operation) else {
                throw MCPReusableSnapshotError.incompatible
            }
            if let bytes,
               try !cooperativelyEqual(owner.source.originalText.utf8, bytes[position], operation: operation) {
                throw MCPReusableSnapshotError.incompatible
            }
        }
    }

    /// Compare existing backing byte-by-byte; no complete text or metadata copy and no retained checkpoint.
    nonisolated func cooperativelyEqual<Left: Sequence, Right: Sequence>(
        _ left: Left, _ right: Right, operation: MCPReadOperation
    ) throws -> Bool where Left.Element == UInt8, Right.Element == UInt8 {
        var lhs = left.makeIterator()
        var rhs = right.makeIterator()
        var untilCheckpoint = 0
        while let byte = lhs.next() {
            if untilCheckpoint == 0 {
                try MCPPortfolioReadEncoding.check(operation)
                untilCheckpoint = 256
            }
            guard let other = rhs.next(), byte == other else {
                try MCPPortfolioReadEncoding.check(operation)
                return false
            }
            untilCheckpoint -= 1
        }
        try MCPPortfolioReadEncoding.check(operation)
        return rhs.next() == nil
    }

    nonisolated func ownerUnion(_ owners: [MCPResultPreparedPage], operation: MCPReadOperation) throws
        -> [MCPResultPreparedPage] {
        var seen: Set<ObjectIdentifier> = []
        var result: [MCPResultPreparedPage] = []
        for owner in owners {
            try MCPPortfolioReadEncoding.check(operation)
            if seen.insert(ObjectIdentifier(owner)).inserted { result.append(owner) }
        }
        return result
    }

    nonisolated func measure(_ owners: [MCPResultPreparedPage], budget: MCPResultRetentionBudget,
                             operation: MCPReadOperation) throws -> MCPResultRetainedBundle {
        try MCPResultPreparation.prepare(pages: owners, budget: budget,
            checkpoint: { try MCPPortfolioReadEncoding.check(operation) })
    }

    nonisolated func rejectForeignOwners(_ entry: MCPReusableSnapshotEntry, rootID: String,
                                         observation: PreparedObservation, operation: MCPReadOperation) throws {
        let identity = try ownerIdentities(entry, operation: operation)
        for index in [observation.index] + observation.pending {
            for (id, existing) in index.entries where id != rootID {
                try MCPPortfolioReadEncoding.check(operation)
                let existingIdentities = try ownerIdentities(existing, operation: operation)
                guard identity.isDisjoint(with: existingIdentities) else {
                    throw PublicationRejection.busy
                }
            }
        }
    }

    nonisolated func ownerIdentities(_ entry: MCPReusableSnapshotEntry, operation: MCPReadOperation) throws
        -> Set<ObjectIdentifier> {
        var result: Set<ObjectIdentifier> = []
        for page in entry.preparedResultBundle?.pages ?? [] {
            try MCPPortfolioReadEncoding.check(operation)
            result.insert(ObjectIdentifier(page))
            if let metadata = page.metadataOwner { result.insert(ObjectIdentifier(metadata)) }
        }
        return result
    }
}
#endif
