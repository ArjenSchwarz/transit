#if os(macOS)
import Foundation

nonisolated struct RetainedView: Sendable {
    let capture: CapturedReadView
    let frozenMetadataBytes: Data
    let window: CompletionWindow
    let initialRequest: MCPPortfolioSummaryRequest
    let firstPage: Data
    let preparedResultPage: MCPResultPreparedPage?

    init(capture: CapturedReadView, frozenMetadataBytes: Data, window: CompletionWindow,
         initialRequest: MCPPortfolioSummaryRequest, firstPage: Data,
         preparedResultPage: MCPResultPreparedPage? = nil) {
        self.capture = capture
        self.frozenMetadataBytes = frozenMetadataBytes
        self.window = window
        self.initialRequest = initialRequest
        self.firstPage = firstPage
        self.preparedResultPage = preparedResultPage
    }
}

nonisolated struct RetentionReservation: Sendable {
    let publication: MCPPublicationReservation
    var id: UUID { publication.operationID }
}

nonisolated struct EncodedViewBundle: Sendable {
    let root: RetainedView
    let pages: [Data]
    let cursors: [String]
    let encodedCaptureByteCount: Int
    let preparedResultBundle: MCPResultRetainedBundle?
    /// Internal lifetime seam: retain with the actual immutable bundle, never invoke manually.
    let lifetimeProbe: (any MCPReusableSnapshotLifetimeProbe)?

    init(root: RetainedView, pages: [Data], cursors: [String], encodedCaptureByteCount: Int,
         lifetimeProbe: (any MCPReusableSnapshotLifetimeProbe)? = nil,
         preparedResultBundle: MCPResultRetainedBundle? = nil) {
        self.root = root
        self.pages = pages
        self.cursors = cursors
        self.encodedCaptureByteCount = encodedCaptureByteCount
        self.lifetimeProbe = lifetimeProbe
        self.preparedResultBundle = preparedResultBundle
    }
}

nonisolated protocol MCPReusableSnapshotLifetimeProbe: AnyObject, Sendable {}

nonisolated struct RetainedPage: Sendable {
    let root: RetainedView
    let encodedPage: Data
    let preparedResultPage: MCPResultPreparedPage?

    init(root: RetainedView, encodedPage: Data, preparedResultPage: MCPResultPreparedPage? = nil) {
        self.root = root
        self.encodedPage = encodedPage
        self.preparedResultPage = preparedResultPage
    }
}

nonisolated enum MCPReusableSnapshotError: Error, Equatable, Sendable {
    case invalidSnapshot
    case invalidCursor
    case incompatible
}

/// Immutable candidates are prepared outside the sole shared publication lock.
/// Root expiry and store versions are checked again by the enclosing response gate.
nonisolated final class MCPReusableSnapshotStore: MCPRetainedViewSource, MCPReadPublicationParticipant {
    let publicationStoreID: MCPPublicationStoreID
    let domain: MCPReadPublicationDomain

    init(domain: MCPReadPublicationDomain) throws {
        self.domain = domain
        self.publicationStoreID = MCPPublicationStoreID(rawValue: UUID())
        try domain.register(storeID: publicationStoreID, index: MCPReusableSnapshotIndex(),
                            maxEntries: 8, maxBytes: 16 * 1024 * 1024)
    }

    func retainedView(for snapshotID: String, now: ContinuousClock.Instant,
                      testingAfterPin: (() throws -> Void)? = nil) throws -> RetainedView {
        try preparedRetainedView(for: snapshotID, now: now, testingAfterPin: testingAfterPin).root
    }

    func preparedRetainedView(for snapshotID: String, now: ContinuousClock.Instant,
                              testingAfterPin: (() throws -> Void)? = nil) throws
        -> (root: RetainedView, pin: MCPReusableSnapshotReadPin) {
        let base = try liveSnapshot(now: now)
        guard let index = base.index as? MCPReusableSnapshotIndex,
              let entry = index.entries[snapshotID] else { throw MCPReusableSnapshotError.invalidSnapshot }
        let pin = MCPReusableSnapshotReadPin(publicationStoreID: publicationStoreID, domain: domain,
            snapshotID: snapshotID, identity: entry.identity, deadline: entry.bundle.root.capture.retentionDeadline,
            cursor: nil)
        try testingAfterPin?()
        let valid = domain.withLock { pin.validateLocked(in: domain) == nil }
        guard valid, now < pin.deadline else { throw MCPReusableSnapshotError.invalidSnapshot }
        return (entry.bundle.root, pin)
    }

    func page(for cursor: String, now: ContinuousClock.Instant,
              testingAfterPin: (() throws -> Void)? = nil) throws -> RetainedPage {
        try preparedPage(for: cursor, now: now, testingAfterPin: testingAfterPin).page
    }

    func preparedPage(for cursor: String, now: ContinuousClock.Instant,
                      testingAfterPin: (() throws -> Void)? = nil) throws
        -> (page: RetainedPage, pin: MCPReusableSnapshotReadPin) {
        guard MCPCursorFamily.classify(cursor) == .reusable else { throw MCPReusableSnapshotError.invalidCursor }
        let base = try liveSnapshot(now: now)
        guard let index = base.index as? MCPReusableSnapshotIndex,
              let snapshotID = index.pageRoots[cursor], let entry = index.entries[snapshotID],
              let bytes = entry.pages[cursor] else { throw MCPReusableSnapshotError.invalidCursor }
        let pin = MCPReusableSnapshotReadPin(publicationStoreID: publicationStoreID, domain: domain,
            snapshotID: snapshotID, identity: entry.identity, deadline: entry.bundle.root.capture.retentionDeadline,
            cursor: cursor)
        try testingAfterPin?()
        let valid = domain.withLock { pin.validateLocked(in: domain) == nil }
        guard valid, now < pin.deadline else { throw MCPReusableSnapshotError.invalidCursor }
        return (RetainedPage(root: entry.bundle.root, encodedPage: bytes), pin)
    }

    func reserveCreate(bundle: EncodedViewBundle, publicationDeadline: ContinuousClock.Instant)
        throws -> RetentionReservation {
        guard bundle.preparedResultBundle == nil, bundle.root.preparedResultPage == nil else {
            throw MCPResultPreparationError.notImplemented
        }
        guard case .completePortfolio = bundle.root.capture.completeness,
              bundle.root.capture.captureScope != .selectedQuery,
              case .initial = bundle.root.initialRequest,
              bundle.root.capture.createdAt.duration(to: bundle.root.capture.retentionDeadline) == .seconds(300),
              !bundle.root.capture.metadata.snapshotId.isEmpty else { throw MCPReusableSnapshotError.incompatible }
        let pages = try pageMapping(pages: bundle.pages, cursors: bundle.cursors)
        let entry = MCPReusableSnapshotEntry(bundle: bundle, pages: pages)
        let rootID = bundle.root.capture.metadata.snapshotId
        let base = try liveSnapshot()
        guard let index = base.index as? MCPReusableSnapshotIndex,
              index.entries[rootID] == nil else { throw PublicationRejection.busy }
        var entries = index.entries
        entries[rootID] = entry
        return try reserve(base: base, candidate: MCPReusableSnapshotIndex(entries: entries),
                           deadline: publicationDeadline)
    }

    func reserveAppend(snapshotID: String, pages: [Data], cursors: [String],
                       publicationDeadline: ContinuousClock.Instant) throws -> RetentionReservation {
        let additions = try pageMapping(pages: pages, cursors: cursors)
        guard !additions.isEmpty else { throw MCPReusableSnapshotError.incompatible }
        let base = try liveSnapshot()
        guard let index = base.index as? MCPReusableSnapshotIndex,
              let root = index.entries[snapshotID] else { throw MCPReusableSnapshotError.invalidSnapshot }
        guard root.preparedResultBundle == nil else { throw MCPReusableSnapshotError.incompatible }
        var mapping = root.pages
        for (cursor, bytes) in additions {
            guard mapping[cursor] == nil else { throw PublicationRejection.busy }
            mapping[cursor] = bytes
        }
        var entries = index.entries
        entries[snapshotID] = MCPReusableSnapshotEntry(identity: root.identity, bundle: root.bundle, pages: mapping)
        return try reserve(base: base, candidate: MCPReusableSnapshotIndex(entries: entries),
                           deadline: publicationDeadline)
    }

    func prepare(reservation: RetentionReservation) throws -> any MCPPreparedPublication {
        let publication = reservation.publication
        guard publication.publicationStoreID == publicationStoreID, publication.domain === domain else {
            throw PublicationRejection.busy
        }
        try domain.withLock {
            if let rejection = publication.validateLocked(in: domain) { throw rejection }
        }
        return publication
    }

    func view(for snapshotID: String, now: ContinuousClock.Instant) throws -> CapturedReadView {
        try retainedView(for: snapshotID, now: now).capture
    }

    func prepareAggregate(
        _ publications: [any MCPPreparedPublication], in domain: MCPReadPublicationDomain
    ) throws -> any MCPPreparedPublication {
        guard domain === self.domain else { throw PublicationRejection.busy }
        let (children, pins) = try publicationParts(publications, in: domain)
        if children.isEmpty {
            guard !pins.isEmpty else { throw PublicationRejection.busy }
            return MCPReusableSnapshotGuardedPublication(publicationStoreID: publicationStoreID,
                domain: domain, pins: pins, mutation: nil)
        }
        if children.count == 1, let child = children.first,
           let candidate = child.index as? MCPReusableSnapshotIndex,
           candidate.entries.values.contains(where: { $0.preparedResultBundle != nil }) {
            if pins.isEmpty { return child }
            return MCPReusableSnapshotGuardedPublication(publicationStoreID: publicationStoreID,
                domain: domain, pins: pins, mutation: child)
        }
        let base = try domain.snapshot(for: publicationStoreID)
        guard let original = base.index as? MCPReusableSnapshotIndex else { throw PublicationRejection.busy }
        var entries = original.entries
        for child in children {
            guard let candidate = child.index as? MCPReusableSnapshotIndex else { throw PublicationRejection.busy }
            entries = try merging(candidate: candidate, original: original, combined: entries)
        }
        let mutation = try domain.transfer(children, aggregateIndex: MCPReusableSnapshotIndex(entries: entries),
                                           operationID: UUID())
        if pins.isEmpty { return mutation }
        return MCPReusableSnapshotGuardedPublication(publicationStoreID: publicationStoreID,
            domain: domain, pins: pins, mutation: mutation)
    }

    private func merging(candidate: MCPReusableSnapshotIndex, original: MCPReusableSnapshotIndex,
                         combined: [String: MCPReusableSnapshotEntry]) throws -> [String: MCPReusableSnapshotEntry] {
        var entries = combined
        for (id, entry) in candidate.entries {
            guard let initial = original.entries[id] else {
                guard entries[id] == nil else { throw PublicationRejection.busy }
                entries[id] = entry
                continue
            }
            guard let current = entries[id] else { throw PublicationRejection.busy }
            guard entry.preparedResultBundle == nil, current.preparedResultBundle == nil,
                  initial.preparedResultBundle == nil, entry.preparedResultPages.isEmpty,
                  current.preparedResultPages.isEmpty,
                  initial.preparedResultPages.isEmpty, entry.bundle.preparedResultBundle == nil,
                  current.bundle.preparedResultBundle == nil, initial.bundle.preparedResultBundle == nil,
                  entry.bundle.root.preparedResultPage == nil, current.bundle.root.preparedResultPage == nil,
                  initial.bundle.root.preparedResultPage == nil else {
                throw MCPResultPreparationError.notImplemented
            }
            var pages = current.pages
            for (token, bytes) in entry.pages where initial.pages[token] == nil {
                guard pages[token] == nil else { throw PublicationRejection.busy }
                pages[token] = bytes
            }
            entries[id] = MCPReusableSnapshotEntry(identity: initial.identity, bundle: initial.bundle, pages: pages)
        }
        return entries
    }

    func rollback(_ reservation: RetentionReservation) throws {
        guard reservation.publication.domain === domain,
              reservation.publication.publicationStoreID == publicationStoreID else {
            throw PublicationRejection.busy
        }
        domain.withLock { reservation.publication.discardLocked(in: domain) }
    }

    func invalidate() throws {
        let empty = try MCPReusableSnapshotIndex()
        // Bounded scalar bookkeeping only; the domain carries old bundles through unlock.
        try domain.withLock {
            guard let state = domain.stores[publicationStoreID] else { throw PublicationRejection.busy }
            domain.retireLocked(state.index)
            state.index = empty
            state.descriptor = empty.descriptor
            state.version &+= 1
            domain.tokenVersion &+= 1
            let pending = Array(state.pending.values)
            for reservation in pending { reservation.discardLocked(in: domain) }
        }
    }

    func pageMapping(pages: [Data], cursors: [String]) throws -> [String: Data] {
        guard pages.count == cursors.count, Set(cursors).count == cursors.count,
              cursors.allSatisfy({ MCPCursorFamily.classify($0) == .reusable }) else {
            throw MCPReusableSnapshotError.incompatible
        }
        return Dictionary(uniqueKeysWithValues: zip(cursors, pages))
    }

    func reserve(base: MCPPublicationStoreSnapshot, candidate: MCPReusableSnapshotIndex,
                 deadline: ContinuousClock.Instant) throws -> RetentionReservation {
        let original = base.index.descriptor
        let descriptor = candidate.descriptor
        // Reject oversize candidates as capacity rather than descriptor-shape contention.
        guard descriptor.entryCount <= 8, descriptor.encodedByteCount <= 16 * 1024 * 1024 else {
            throw PublicationRejection.capacity
        }
        let (entryDelta, entryOverflow) = descriptor.entryCount.subtractingReportingOverflow(original.entryCount)
        let (byteDelta, byteOverflow) = descriptor.encodedByteCount
            .subtractingReportingOverflow(original.encodedByteCount)
        guard !entryOverflow, !byteOverflow, entryDelta >= 0, byteDelta >= 0 else { throw PublicationRejection.busy }
        let publication = try domain.reserve(storeID: publicationStoreID, operationID: UUID(),
            expectedVersion: base.version, expectedTokenVersion: base.tokenVersion, index: candidate,
            chargeEntries: entryDelta, chargeBytes: byteDelta,
            newTokens: descriptor.tokens.subtracting(original.tokens), deadline: deadline)
        return RetentionReservation(publication: publication)
    }

    /// Expiry removal is prepared outside the domain; a competing swap produces busy.
    func liveSnapshot(now: ContinuousClock.Instant? = nil) throws -> MCPPublicationStoreSnapshot {
        let instant = now ?? domain.withLock { domain.currentInstantLocked }
        let base = try domain.snapshot(for: publicationStoreID)
        guard let original = base.index as? MCPReusableSnapshotIndex else { throw PublicationRejection.busy }
        let entries = original.entries.filter { instant < $0.value.bundle.root.capture.retentionDeadline }
        guard entries.count != original.entries.count else { return base }
        let replacement = try MCPReusableSnapshotIndex(entries: entries)
        try domain.retire(storeID: publicationStoreID, expectedVersion: base.version, replacementIndex: replacement)
        return try domain.snapshot(for: publicationStoreID)
    }
}

extension MCPReusableSnapshotStore {
    nonisolated func publicationParts(
        _ publications: [any MCPPreparedPublication], in domain: MCPReadPublicationDomain
    ) throws -> ([MCPPublicationReservation], [MCPReusableSnapshotReadPin]) {
        var children: [MCPPublicationReservation] = []
        var pins: [MCPReusableSnapshotReadPin] = []
        for publication in publications {
            guard publication.publicationStoreID == publicationStoreID else { throw PublicationRejection.busy }
            switch publication {
            case let pin as MCPReusableSnapshotReadPin:
                guard pin.domain === domain else { throw PublicationRejection.busy }
                pins.append(pin)
            case let combined as MCPReusableSnapshotGuardedPublication:
                let mutation = try checkedMutation(combined, in: domain)
                pins += combined.pins
                if let mutation { children.append(mutation) }
            case let child as MCPPublicationReservation:
                guard child.domain === domain else { throw PublicationRejection.busy }
                children.append(child)
            default: throw PublicationRejection.busy
            }
        }
        return (children, try compactPins(pins, in: domain))
    }

    nonisolated private func checkedMutation(
        _ combined: MCPReusableSnapshotGuardedPublication, in domain: MCPReadPublicationDomain
    ) throws -> MCPPublicationReservation? {
        guard combined.domain === domain,
              combined.mutation.map({ mutation in
                  mutation.domain === domain && mutation.publicationStoreID == publicationStoreID
              }) ?? true else {
            throw PublicationRejection.busy
        }
        return combined.mutation
    }

    nonisolated private func compactPins(_ pins: [MCPReusableSnapshotReadPin], in domain: MCPReadPublicationDomain)
        throws -> [MCPReusableSnapshotReadPin] {
        var roots: [String: MCPReusableSnapshotReadPin] = [:]
        for pin in pins {
            guard pin.domain === domain, pin.publicationStoreID == publicationStoreID else {
                throw PublicationRejection.busy
            }
            if let prior = roots[pin.snapshotID] {
                guard prior.identity == pin.identity, prior.deadline == pin.deadline else {
                    throw PublicationRejection.busy
                }
            }
            // Pages are append-only for an immutable root identity. Root identity/lifetime
            // implies preservation of every cursor validated during its atomic lookup.
            roots[pin.snapshotID] = MCPReusableSnapshotReadPin(publicationStoreID: publicationStoreID,
                domain: domain, snapshotID: pin.snapshotID, identity: pin.identity, deadline: pin.deadline, cursor: nil)
        }
        guard roots.count <= 8 else { throw PublicationRejection.busy }
        return roots.keys.sorted().compactMap { roots[$0] }
    }
}

#endif
