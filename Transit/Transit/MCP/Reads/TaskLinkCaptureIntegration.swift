#if os(macOS)
import Foundation
import SwiftData

@MainActor
enum TaskLinkCaptureIntegration {
    static func graph(
        _ request: ReadCaptureRequest, context: ModelContext, instant: Date
    ) throws -> TaskLinkGraphView? {
        switch request.selection {
        case .tasks, .portfolio:
            return try TaskLinkService.graph(in: context, evaluationInstant: instant,
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
