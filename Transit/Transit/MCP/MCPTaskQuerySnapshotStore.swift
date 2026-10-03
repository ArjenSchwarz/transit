#if os(macOS)
import Foundation

@MainActor
final class MCPTaskQuerySnapshotStore {
    private struct Snapshot {
        let deadline: ContinuousClock.Instant
        let pages: [String: String]
        let byteCount: Int
    }

    let now: () -> ContinuousClock.Instant
    let wallNow: () -> Date
    let makeCursor: () -> String
    let maxBytes: Int
    private let maxSnapshots: Int
    private var snapshots: [Snapshot] = []
    private(set) var retainedBytes = 0

    init(
        now: @escaping () -> ContinuousClock.Instant = { .now },
        wallNow: @escaping () -> Date = Date.init,
        makeCursor: @escaping () -> String = { UUID().uuidString },
        maxSnapshots: Int = 8,
        maxBytes: Int = 16 * 1024 * 1024
    ) {
        self.now = now
        self.wallNow = wallNow
        self.makeCursor = makeCursor
        self.maxSnapshots = maxSnapshots
        self.maxBytes = maxBytes
    }

    func purgeExpired() {
        let instant = now()
        snapshots.removeAll { instant >= $0.deadline }
        retainedBytes = snapshots.reduce(0) { $0 + $1.byteCount }
    }

    func publish(pages: [String], cursors: [String], deadline: ContinuousClock.Instant) throws {
        purgeExpired()
        guard now() < deadline else {
            throw MCPTaskQueryError(code: "QUERY_EXPIRED",
                                    message: "Query expired during preparation; start a new query")
        }
        let bytes = pages.reduce(0) { $0 + $1.utf8.count }
        guard bytes <= maxBytes else { throw capacityError() }
        guard !pages.isEmpty, cursors.count == pages.count - 1,
              Set(cursors).count == cursors.count,
              cursors.allSatisfy({ token in
                  UUID(uuidString: token) != nil && !snapshots.contains { $0.pages[token] != nil }
              }) else {
            throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Could not publish query pages")
        }
        guard pages.count > 1 else { return }
        guard snapshots.count < maxSnapshots, retainedBytes <= maxBytes - bytes else { throw capacityError() }
        let mapping = Dictionary(uniqueKeysWithValues: zip(cursors, pages.dropFirst()))
        snapshots.append(Snapshot(deadline: deadline, pages: mapping, byteCount: bytes))
        retainedBytes += bytes
    }

    func page(for cursor: String) throws -> String {
        purgeExpired()
        guard let page = snapshots.lazy.compactMap({ $0.pages[cursor] }).first else {
            throw MCPTaskQueryError(code: "INVALID_CURSOR", message: "Unknown or expired cursor; start a new query")
        }
        return page
    }

    func clear() {
        snapshots.removeAll()
        retainedBytes = 0
    }

    func capacityError() -> MCPTaskQueryError {
        MCPTaskQueryError(code: "QUERY_CAPACITY_EXCEEDED",
                          message: "Query capacity exceeded; reduce scope/comments or retry after expiry")
    }
}
#endif
