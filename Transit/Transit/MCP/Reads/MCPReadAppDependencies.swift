#if os(macOS)
import Foundation
import SwiftData

@MainActor enum MCPReadAppDependencies {
    static func make(container: ModelContainer, syncActive: Bool) -> MCPReadService {
        let domain = MCPReadPublicationDomain()
        let snapshots = MCPTaskQuerySnapshotStore(domain: domain)
        let monitor = MCPImportEvidenceMonitor(syncActive: syncActive, storeIdentifier: storeIdentifier(container))
        monitor.start()
        let source = MCPReadCaptureBuilder(container: container, generation: { monitor.snapshot().generation })
        let service = MCPReadService(source: source, monitor: monitor, snapshots: snapshots)
        return service
    }

    /// Public history identity only; no import applicability or visibility is manufactured.
    private static func storeIdentifier(_ container: ModelContainer) -> String? {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>(
            sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let transaction = try? context.fetchHistory(descriptor).first,
              !transaction.storeIdentifier.isEmpty else { return nil }
        return transaction.storeIdentifier
    }
}
#endif
