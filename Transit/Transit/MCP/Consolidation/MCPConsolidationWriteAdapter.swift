#if os(macOS)
import Foundation
import SwiftData

/// Installs consolidation only in the existing clean owned-context policy.
@MainActor final class MCPConsolidationWriteAdapter {
    private let taskAllocator: DisplayIDAllocator
    private let milestoneAllocator: DisplayIDAllocator
    private let configuration: TaskConsolidationService.Configuration

    init(taskAllocator: DisplayIDAllocator, milestoneAllocator: DisplayIDAllocator,
         configuration: TaskConsolidationService.Configuration) {
        self.taskAllocator = taskAllocator
        self.milestoneAllocator = milestoneAllocator
        self.configuration = configuration
    }

    func policy() -> MCPBatchWritePolicy {
        MCPBatchWritePolicy(makeCommitServices: { [taskAllocator, milestoneAllocator, configuration] context in
            MCPWriteCommitServices(context: context, taskAllocator: taskAllocator,
                milestoneAllocator: milestoneAllocator, consolidation: configuration)
        }, validateBeforeApply: { _, context in
            guard !context.hasChanges, !context.autosaveEnabled else {
                throw MCPWriteFailure("OUTCOME_UNCERTAIN", "Consolidation needs clean owned services")
            }
        })
    }
}
#endif
