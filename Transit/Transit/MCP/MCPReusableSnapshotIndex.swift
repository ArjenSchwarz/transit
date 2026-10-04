#if os(macOS)
import Foundation

/// The original bundle remains owned by every replacement entry, including its lifetime probe.
nonisolated struct MCPReusableSnapshotEntry: Sendable {
    let identity: UUID
    let bundle: EncodedViewBundle
    let pages: [String: Data]

    init(identity: UUID = UUID(), bundle: EncodedViewBundle, pages: [String: Data]) {
        self.identity = identity
        self.bundle = bundle
        self.pages = pages
    }

    func descriptor() throws -> MCPPublicationRoot {
        let id = bundle.root.capture.metadata.snapshotId
        guard bundle.encodedCaptureByteCount >= 0, pages[id] == nil else {
            throw MCPReusableSnapshotError.incompatible
        }
        let bytes = try ([bundle.encodedCaptureByteCount, bundle.root.firstPage.count]
            + pages.values.map(\.count)).reduce(0) { sum, value in
                let (total, overflow) = sum.addingReportingOverflow(value)
                guard !overflow else { throw PublicationRejection.capacity }
                return total
            }
        return MCPPublicationRoot(id: id, deadline: bundle.root.capture.retentionDeadline,
                                  encodedByteCount: bytes, tokens: Set(pages.keys).union([id]))
    }
}

/// Built and pinned outside the shared gate; its descriptor contains bounded root bookkeeping.
nonisolated final class MCPReusableSnapshotIndex: MCPPublicationIndex {
    let descriptor: MCPPublicationIndexDescriptor
    let entries: [String: MCPReusableSnapshotEntry]
    let pageRoots: [String: String]

    init(entries: [String: MCPReusableSnapshotEntry] = [:]) throws {
        self.entries = entries
        self.descriptor = try MCPPublicationIndexDescriptor(roots: entries.values.map { try $0.descriptor() })
        var mapping: [String: String] = [:]
        for (id, entry) in entries {
            guard id == entry.bundle.root.capture.metadata.snapshotId else { throw PublicationRejection.busy }
            for cursor in entry.pages.keys {
                guard mapping[cursor] == nil else { throw PublicationRejection.busy }
                mapping[cursor] = id
            }
        }
        self.pageRoots = mapping
    }
}
#endif
