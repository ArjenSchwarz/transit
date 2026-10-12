import Foundation
import SwiftData

nonisolated enum SavedReadBoundaryError: Error { case incoherentCapture }

/// Reused stable-history boundary; purged history is never proof of an empty store.
nonisolated enum SavedReadBoundary {
    static func watermark(_ container: ModelContainer) throws -> DefaultHistoryTransaction? {
        guard container.configurations.count == 1 else { throw SavedReadBoundaryError.incoherentCapture }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            var descriptor = HistoryDescriptor<DefaultHistoryTransaction>(
                sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)])
            descriptor.fetchLimit = 1
            if let transaction = try context.fetchHistory(descriptor).first {
                guard !transaction.storeIdentifier.isEmpty else { throw SavedReadBoundaryError.incoherentCapture }
                return transaction
            }
            // An empty selection does not prove an empty store. History can have been purged.
            guard try context.fetchCount(FetchDescriptor<Project>()) == 0,
                  try context.fetchCount(FetchDescriptor<TransitTask>()) == 0,
                  try context.fetchCount(FetchDescriptor<Milestone>()) == 0,
                  try context.fetchCount(FetchDescriptor<Comment>()) == 0,
                  try context.fetchCount(FetchDescriptor<SyncHeartbeat>()) == 0,
                  try context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0,
                  try context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 0,
                  try context.fetchCount(FetchDescriptor<TaskLinkRemovalEvidence>()) == 0,
                  try context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 0 else {
                throw SavedReadBoundaryError.incoherentCapture
            }
            return nil
        } catch {
            throw SavedReadBoundaryError.incoherentCapture
        }
    }
}
