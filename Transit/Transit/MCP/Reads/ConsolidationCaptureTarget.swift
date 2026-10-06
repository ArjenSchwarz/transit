#if os(macOS)
import Foundation
import SwiftData

nonisolated enum ConsolidationCaptureTarget: Sendable {
    case group([UUID])
    case operation(UUID)

    @MainActor func resolve(in context: ModelContext, budget: TaskLinkGraphBudget) throws
        -> ConsolidationCaptureSelection {
        try budget.check()
        switch self {
        case .group(let ids): return .init(selectedTaskIds: ids)
        case .operation(let id):
            var descriptor = FetchDescriptor<TaskConsolidationEvent>(predicate: #Predicate { $0.operationId == id })
            descriptor.includePendingChanges = false
            guard try context.fetchCount(descriptor) <= 2 else { throw TaskConsolidationHistoryError.ambiguous }
            let events = try context.fetch(descriptor).map { row in
                try budget.check()
                guard row.payloadJSON.utf8.count <= min(budget.maximumBytes, 256 * 1_024) else {
                    throw TaskLinkGraphError.capacityExceeded
                }
                return try TaskConsolidationEventValue.capture(row)
            }
            let history = try TaskConsolidationHistoryCodec.history(events, operationId: id)
            return .init(selectedTaskIds: [history.apply.survivorTaskId] + history.apply.candidateTaskIds,
                operationId: id, requireSelectedOriginals: false)
        }
    }
}
#endif
