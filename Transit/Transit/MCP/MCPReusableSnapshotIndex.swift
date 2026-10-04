#if os(macOS)
import Foundation

/// The original bundle remains owned by every replacement entry, including its lifetime probe.
nonisolated struct MCPReusableSnapshotEntry: Sendable {
    let identity: UUID
    let bundle: EncodedViewBundle
    let pages: [String: Data]
    let preparedResultBundle: MCPResultRetainedBundle?
    let preparedResultPages: [String: MCPResultPreparedPage]

    init(identity: UUID = UUID(), bundle: EncodedViewBundle, pages: [String: Data],
         preparedResultPages: [String: MCPResultPreparedPage] = [:],
         preparedResultBundle: MCPResultRetainedBundle? = nil) {
        self.identity = identity
        self.bundle = bundle
        self.pages = pages
        self.preparedResultPages = preparedResultPages
        self.preparedResultBundle = preparedResultBundle
    }

    func descriptor(checkpoint: () throws -> Void = {}) throws -> MCPPublicationRoot {
        try checkpoint()
        let id = bundle.root.capture.metadata.snapshotId
        guard bundle.encodedCaptureByteCount >= 0, pages[id] == nil else {
            throw MCPReusableSnapshotError.incompatible
        }
        let (initialBytes, initialOverflow) = bundle.encodedCaptureByteCount
            .addingReportingOverflow(bundle.root.firstPage.count)
        guard !initialOverflow else { throw PublicationRejection.capacity }
        var legacyBytes = initialBytes
        for data in pages.values {
            try checkpoint()
            let value = data.count
            let sum = legacyBytes
            let (total, overflow) = sum.addingReportingOverflow(value)
            guard !overflow else { throw PublicationRejection.capacity }
            legacyBytes = total
        }
        if let preparedResultBundle {
            guard bundle.preparedResultBundle == nil,
                  preparedResultBundle.charge.originalCaptureIndexBytes == legacyBytes,
                  let first = bundle.root.preparedResultPage,
                  try preparedResultBundle.pages.contains(where: {
                      try checkpoint()
                      return $0 === first
                  }),
                  Set(preparedResultPages.keys) == Set(pages.keys),
                  try preparedResultPages.values.allSatisfy({ owner in
                      try checkpoint()
                      return try preparedResultBundle.pages.contains(where: {
                          try checkpoint()
                          return $0 === owner
                      })
                  }) else { throw MCPReusableSnapshotError.incompatible }
        } else {
            guard bundle.preparedResultBundle == nil, bundle.root.preparedResultPage == nil,
                  preparedResultPages.isEmpty else { throw MCPReusableSnapshotError.incompatible }
        }
        return MCPPublicationRoot(id: id, deadline: bundle.root.capture.retentionDeadline,
            encodedByteCount: preparedResultBundle?.charge.totalBytes ?? legacyBytes,
            tokens: Set(pages.keys).union([id]))
    }
}

/// Built and pinned outside the shared gate; its descriptor contains bounded root bookkeeping.
nonisolated final class MCPReusableSnapshotIndex: MCPPublicationIndex {
    let descriptor: MCPPublicationIndexDescriptor
    let entries: [String: MCPReusableSnapshotEntry]
    let pageRoots: [String: String]

    init(entries: [String: MCPReusableSnapshotEntry] = [:], checkpoint: () throws -> Void = {}) throws {
        self.entries = entries
        self.descriptor = try MCPPublicationIndexDescriptor(roots: entries.values.map {
            try $0.descriptor(checkpoint: checkpoint)
        })
        var mapping: [String: String] = [:]
        var identities: Set<ObjectIdentifier> = []
        for (id, entry) in entries {
            try checkpoint()
            var rootIdentities: Set<ObjectIdentifier> = []
            for page in entry.preparedResultBundle?.pages ?? [] {
                try checkpoint()
                rootIdentities.insert(ObjectIdentifier(page))
                if let metadata = page.metadataOwner { rootIdentities.insert(ObjectIdentifier(metadata)) }
            }
            guard identities.isDisjoint(with: rootIdentities) else { throw PublicationRejection.busy }
            identities.formUnion(rootIdentities)
            guard id == entry.bundle.root.capture.metadata.snapshotId else { throw PublicationRejection.busy }
            for cursor in entry.pages.keys {
                try checkpoint()
                guard mapping[cursor] == nil else { throw PublicationRejection.busy }
                mapping[cursor] = id
            }
        }
        self.pageRoots = mapping
    }
}
#endif
