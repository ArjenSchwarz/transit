#if os(macOS)
import Foundation
import SwiftData

@MainActor struct ReadCaptureFetchedEntities {
    let tasks: [TransitTask]
    let milestones: [Milestone]
    let tasksCaptured: Bool
}

@MainActor
enum TaskLinkCaptureIntegration {
    static func graph(
        _ request: ReadCaptureRequest, in context: ModelContext,
        _ entities: ReadCaptureFetchedEntities, at instant: Date
    ) throws -> TaskLinkGraphView? {
        switch request.selection {
        case .tasks, .portfolio:
            guard entities.tasksCaptured else { return nil }
            return try TaskLinkService.graph(in: context, capturedTasks: entities.tasks, evaluationInstant: instant,
                                             budget: request.taskLinkBudget ?? TaskLinkGraphBudget())
        case .projects, .projectCatalog, .milestones: return nil
        }
    }
}
extension ReadCaptureRequest {
    @MainActor
    func taskBodyKeys(_ values: [ReadTaskSelectionValue], graph: TaskLinkGraphView?) throws -> Set<LocalRecordKey> {
        let keys = try selectTaskBodies?(values) ?? Set(values.map(\.physicalKey))
        guard let options = taskLinkOptions else { return keys }
        let budget = taskLinkBudget ?? TaskLinkGraphBudget()
        return try Set(values.compactMap { task in
            try budget.check()
            guard keys.contains(task.physicalKey), try options.matches(task.id, graph: graph, budget: budget)
            else { return nil }
            return task.physicalKey
        })
    }

}
#endif
