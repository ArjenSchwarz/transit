import Foundation
import SwiftData

nonisolated struct TaskConsolidationNativeObservation: Codable, Sendable {
    let taskId: UUID
    let history: [ConsolidationHistoryProjection]
    let tasks: [TaskLinkTaskValue]
    let problem: String?
}

/// Uses the app's shared eight-permit read domain. No fallback coordinator is created.
@MainActor final class TaskConsolidationNativeReader {
    private let capture: TaskConsolidationSavedCapture
    private let maximumBytes: Int
    nonisolated let coordinator: MCPReadCoordinator

    init(container: ModelContainer, coordinator: MCPReadCoordinator,
         fence: ConsolidationCaptureFence = .persistentHistory, maximumBytes: Int = 16 * 1_024 * 1_024) {
        self.capture = TaskConsolidationSavedCapture(container: container, fence: fence)
        self.coordinator = coordinator
        self.maximumBytes = maximumBytes
    }

    func read(_ id: UUID) async -> TaskConsolidationNativeObservation {
        let unavailable = TaskConsolidationNativeObservation(taskId: id, history: [], tasks: [],
            problem: "Saved consolidation history is unavailable. Retry after the current read finishes.")
        return await coordinator.executeValue(unavailable: unavailable) { [self] operation in
            operation.beginActorQueue()
            return try await MainActor.run {
                operation.finishActorQueue()
                let budget = TaskLinkGraphBudget(deadline: operation.diagnosticContext.internalCutoff,
                    maximumBytes: maximumBytes,
                    checkpoint: {
                        guard operation.shouldContinue() else { throw CancellationError() }
                        try Task.checkCancellation()
                    })
                do {
                    let evidence = try capture.capture(selectedTaskIds: [id], budget: budget)
                    try budget.check()
                    return TaskConsolidationNativeObservation(taskId: id, history: evidence.history,
                        tasks: evidence.graph.tasks, problem: nil)
                } catch TaskLinkGraphError.capacityExceeded {
                    return TaskConsolidationNativeObservation(taskId: id, history: [], tasks: [],
                        problem: "Complete saved consolidation history exceeds the 16 MiB read limit.")
                }
            }
        }
    }
}
