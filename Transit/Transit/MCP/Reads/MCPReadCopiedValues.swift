#if os(macOS)
import Foundation

@MainActor struct MCPReadCopiedValues {
    let scope: ReadCaptureScope
    let projects: [ReadProject]
    let tasks: [ReadTask]
    let milestones: [ReadMilestone]
    let comments: [ReadCommentEvidence]
    let taskLinkGraph: TaskLinkGraphView?
    let consolidationEvidence: ConsolidationSavedEvidence?
    func retaining(_ evidence: ConsolidationSavedEvidence?) -> Self {
        Self(scope: scope, projects: projects, tasks: tasks, milestones: milestones, comments: comments,
            taskLinkGraph: taskLinkGraph, consolidationEvidence: evidence)
    }
}
#endif
