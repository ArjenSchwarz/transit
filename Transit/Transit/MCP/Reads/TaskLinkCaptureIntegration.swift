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
#endif
