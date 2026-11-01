import SwiftData

/// Fresh preparation must never authorize replacement of a populated local graph either.
enum MigrationLocalInspection {
    static func isEmpty(_ container: ModelContainer) throws -> Bool {
        let context = ModelContext(container)
        return try context.fetchCount(FetchDescriptor<Project>()) == 0
            && context.fetchCount(FetchDescriptor<TransitTask>()) == 0
            && context.fetchCount(FetchDescriptor<Milestone>()) == 0
            && context.fetchCount(FetchDescriptor<Comment>()) == 0
            && context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0
            && context.fetchCount(FetchDescriptor<TaskLinkOccurrence>()) == 0
            && context.fetchCount(FetchDescriptor<TaskLinkRemovalEvidence>()) == 0
            && context.fetchCount(FetchDescriptor<TaskConsolidationEvent>()) == 0
    }
}
