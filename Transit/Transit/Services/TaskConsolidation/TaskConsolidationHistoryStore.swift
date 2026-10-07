import Foundation
import SwiftData
extension TaskConsolidationRawFields {
    @MainActor static func capture(_ task: TransitTask) throws -> Self {
        Self(description: task.taskDescription, metadataJSON: task.metadataJSON, statusRawValue: task.statusRawValue,
            lastStatusChangeDate: try exactDate(task.lastStatusChangeDate),
            completionDate: try task.completionDate.map(exactDate))
    }
}
extension TaskConsolidationEventValue {
    @MainActor static func capture(_ event: TaskConsolidationEvent) throws -> Self {
        Self(physicalKey: try JSONEncoder().encode(event.persistentModelID), id: event.id,
            operationId: event.operationId, kind: event.kindRawValue,
            createdAt: try TaskConsolidationRawFields.exactDate(event.createdAt),
            originScopeId: event.originScopeId, survivorTaskId: event.survivorTaskId,
            candidateSlots: [event.candidate1, event.candidate2, event.candidate3, event.candidate4, event.candidate5],
            payloadJSON: event.payloadJSON)
    }
}
@MainActor enum TaskConsolidationHistoryStore {
    static func savedEvents(operationId: UUID, in context: ModelContext,
                            budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws
        -> [TaskConsolidationEventValue] {
        var descriptor = FetchDescriptor<TaskConsolidationEvent>(
            predicate: #Predicate { $0.operationId == operationId })
        descriptor.includePendingChanges = false
        try budget.check()
        guard try context.fetchCount(descriptor) <= 2 else { throw TaskConsolidationHistoryError.ambiguous }
        return try context.fetch(descriptor).map { row in
            try budget.check()
            guard row.payloadJSON.utf8.count <= min(budget.maximumBytes, 256 * 1_024) else {
                throw TaskConsolidationHistoryError.capacityExceeded
            }
            return try TaskConsolidationEventValue.capture(row)
        }
    }
}
