#if os(macOS)
import Foundation

nonisolated struct MCPRetainedQueryPage: Sendable {
    private let legacyText: String?
    var text: String { preparedResultPage?.source.originalText ?? legacyText ?? "" }
    let metadataBytes: Data?
    let policy: MCPReadPolicy?
    let preparedResultPage: MCPResultPreparedPage?

    init(text: String, metadataBytes: Data?, policy: MCPReadPolicy?,
         preparedResultPage: MCPResultPreparedPage? = nil) {
        self.legacyText = preparedResultPage == nil ? text : nil
        self.metadataBytes = metadataBytes
        self.policy = policy
        self.preparedResultPage = preparedResultPage
    }
}

nonisolated enum MCPCursorFamily: Sendable {
    case ordinary, reusable
    static func classify(_ token: String) -> Self? {
        guard let uuid = UUID(uuidString: token) else { return nil }
        switch uuid.uuid.6 >> 4 {
        case 4: return .ordinary
        case 8: return .reusable
        default: return nil
        }
    }
}

@MainActor
final class MCPTaskQuerySnapshotStore: MCPReadPublicationParticipant {
    nonisolated final class Index: MCPPublicationIndex {
        let descriptor: MCPPublicationIndexDescriptor
        let pages: [String: MCPRetainedQueryPage]
        let modernRoots: [String: ModernRoot]
        init(roots: [MCPPublicationRoot] = [], pages: [String: MCPRetainedQueryPage] = [:],
             modernRoots: [String: ModernRoot] = [:]) throws {
            descriptor = try MCPPublicationIndexDescriptor(roots: roots)
            self.pages = pages
            self.modernRoots = modernRoots
        }
    }

    let now: () -> ContinuousClock.Instant
    let wallNow: () -> Date
    let makeCursor: () -> String
    let maxBytes: Int
    nonisolated let publicationStoreID = MCPPublicationStoreID(rawValue: UUID())
    nonisolated let domain: MCPReadPublicationDomain
    var retainedBytes: Int { (try? domain.accounting(for: publicationStoreID).visibleBytes) ?? 0 }

    init(now: @escaping () -> ContinuousClock.Instant = { .now },
         wallNow: @escaping () -> Date = Date.init,
         makeCursor: @escaping () -> String = { UUID().uuidString },
         maxSnapshots: Int = 8, maxBytes: Int = 16 * 1024 * 1024,
         domain: MCPReadPublicationDomain? = nil) {
        self.now = now
        self.wallNow = wallNow
        self.makeCursor = makeCursor
        self.maxBytes = maxBytes
        self.domain = domain ?? MCPReadPublicationDomain()
        // Fresh private store identity and an empty index cannot collide.
        do {
            try self.domain.register(storeID: publicationStoreID, index: Index(),
                                     maxEntries: maxSnapshots, maxBytes: maxBytes)
        } catch {
            preconditionFailure("Invalid ordinary retention store configuration: \(error)")
        }
    }

    func purgeExpired() {
        guard let base = try? domain.snapshot(for: publicationStoreID), let index = base.index as? Index else { return }
        let instant = now()
        let roots = index.descriptor.roots.values.filter { instant < $0.deadline }
        guard roots.count != index.descriptor.entryCount else { return }
        let tokens = roots.reduce(into: Set<String>()) { $0.formUnion($1.tokens) }
        guard let replacement = try? Index(roots: roots, pages: index.pages.filter { tokens.contains($0.key) },
                                           modernRoots: index.modernRoots.filter { key, _ in
                                               roots.contains { $0.id == key }
                                           }) else {
            return
        }
        try? domain.retire(storeID: publicationStoreID, expectedVersion: base.version, replacementIndex: replacement)
    }

    /// Builds a complete private index and reserves capacity; visibility waits for the response gate.
    func prepare(pages: [String], cursors: [String], deadline: ContinuousClock.Instant,
                 operationID: UUID, metadataBytes: Data? = nil, policy: MCPReadPolicy? = nil)
        throws -> MCPPublicationReservation? {
        purgeExpired()
        guard now() < deadline else { throw expiryError() }
        let bytes = pages.reduce(0) { $0 + $1.utf8.count + (metadataBytes?.count ?? 0) }
        guard bytes <= maxBytes else { throw capacityError() }
        guard !pages.isEmpty, cursors.count == pages.count - 1,
              Set(cursors).count == cursors.count,
              cursors.allSatisfy({ MCPCursorFamily.classify($0) == .ordinary }) else {
            throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Could not publish query pages")
        }
        guard pages.count > 1 else { return nil }
        let base = try domain.snapshot(for: publicationStoreID)
        guard let original = base.index as? Index else { throw PublicationRejection.busy }
        guard base.allocatedTokenSets.allSatisfy({ Set(cursors).isDisjoint(with: $0) }) else {
            throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Could not publish query pages")
        }
        let id = UUID().uuidString
        let root = MCPPublicationRoot(id: id, deadline: deadline, encodedByteCount: bytes,
                                      tokens: Set(cursors).union([id]))
        var mapping = original.pages
        for (token, text) in zip(cursors, pages.dropFirst()) {
            mapping[token] = MCPRetainedQueryPage(text: text, metadataBytes: metadataBytes, policy: policy)
        }
        let candidate = try Index(roots: Array(original.descriptor.roots.values) + [root], pages: mapping,
                                  modernRoots: original.modernRoots)
        do {
            return try domain.reserve(storeID: publicationStoreID, operationID: operationID,
                expectedVersion: base.version, expectedTokenVersion: base.tokenVersion, index: candidate,
                chargeEntries: 1, chargeBytes: bytes, newTokens: root.tokens, deadline: deadline)
        } catch PublicationRejection.capacity { throw capacityError() } catch PublicationRejection.expired {
            throw expiryError()
        }
    }

    func publish(pages: [String], cursors: [String], deadline: ContinuousClock.Instant) throws {
        guard let reservation = try prepare(pages: pages, cursors: cursors, deadline: deadline,
                                            operationID: UUID()) else { return }
        let rejection = domain.withLock { () -> PublicationRejection? in
            if let rejection = reservation.validateLocked(in: domain) {
                reservation.discardLocked(in: domain)
                return rejection
            }
            reservation.commitLocked(in: domain)
            return nil
        }
        if let rejection {
            if rejection == .expired { throw expiryError() }
            throw MCPTaskQueryError(code: "READ_BUSY", message: "Query publication changed; retry with backoff")
        }
    }

    func retainedPage(for cursor: String) throws -> MCPRetainedQueryPage {
        try preparedRetainedPage(for: cursor).page
    }

    func preparedRetainedPage(for cursor: String) throws
        -> (page: MCPRetainedQueryPage, pin: MCPOrdinaryQueryReadPin) {
        purgeExpired()
        let base = try domain.snapshot(for: publicationStoreID)
        guard let index = base.index as? Index else { throw PublicationRejection.busy }
        // Lookup and token->root work is outside the gate; pin/version and bounded
        // original root expiry are checked together before returning frozen bytes.
        guard let page = index.pages[cursor],
              let root = index.descriptor.roots.values.first(where: { $0.tokens.contains(cursor) }) else {
            throw cursorError()
        }
        let pin = MCPOrdinaryQueryReadPin(publicationStoreID: publicationStoreID, domain: domain,
            rootID: root.id, cursor: cursor, deadline: root.deadline)
        let valid = domain.withLock { pin.validateLocked(in: domain) == nil }
        guard valid else { throw cursorError() }
        return (page, pin)
    }

    func page(for cursor: String) throws -> String { try retainedPage(for: cursor).text }

    func clear() {
        guard let base = try? domain.snapshot(for: publicationStoreID), let empty = try? Index() else { return }
        try? domain.retire(storeID: publicationStoreID, expectedVersion: base.version, replacementIndex: empty)
    }

    nonisolated func prepareAggregate(
        _ publications: [any MCPPreparedPublication], in domain: MCPReadPublicationDomain
    ) throws -> any MCPPreparedPublication {
        try prepareAggregate(publications, in: domain, checking: nil)
    }

    func capacityError() -> MCPTaskQueryError {
        MCPTaskQueryError(code: "QUERY_CAPACITY_EXCEEDED",
                          message: "Query capacity exceeded; reduce scope/comments or retry after expiry")
    }

    func expiryError() -> MCPTaskQueryError {
        MCPTaskQueryError(code: "QUERY_EXPIRED", message: "Query expired during preparation; start a new query")
    }

    private func cursorError() -> MCPTaskQueryError {
        MCPTaskQueryError(code: "INVALID_CURSOR", message: "Unknown or expired cursor; start a new query")
    }
}
#endif
