#if os(macOS)
import Foundation
import SwiftData

/// Only this feature adapter can mint capability. It binds full saved validation
/// and exact owned apply to one operation's services and prepared identity.
@MainActor struct TaskLinkWriteCapability {
    let validatePrepared: (MCPWriteCommand, PreparedMCPWrite, MCPWriteCommandServices) throws -> Void
    fileprivate init(
        _ validation: @escaping (MCPWriteCommand, PreparedMCPWrite, MCPWriteCommandServices) throws -> Void
    ) {
        validatePrepared = validation
    }
}

@MainActor final class TaskLinkWriteAdapter {
    private let taskAllocator: DisplayIDAllocator
    private let milestoneAllocator: DisplayIDAllocator

    init(taskAllocator: DisplayIDAllocator, milestoneAllocator: DisplayIDAllocator) {
        self.taskAllocator = taskAllocator
        self.milestoneAllocator = milestoneAllocator
    }

    /// A new plan holder for each standalone request/per-item batch operation;
    /// no plan survives an await, result replay or the owned commit phase.
    func policy(onPendingEditsStop: @escaping @MainActor () -> Void = {}) -> MCPBatchWritePolicy {
        let owned = TaskLinkOwnedPlan()
        return MCPBatchWritePolicy(makeCommitServices: { [taskAllocator, milestoneAllocator] context in
            MCPWriteCommitServices(context: context, taskAllocator: taskAllocator,
                                   milestoneAllocator: milestoneAllocator)
        }, onPendingEditsStop: onPendingEditsStop, afterTaskApply: { command, task, services in
            try owned.apply(command, task: task, services: services)
        }, taskLinkCapability: TaskLinkWriteCapability { command, prepared, services in
            try owned.validate(command, prepared: prepared, services: services)
        }, validateBeforeApply: { _, context in
            guard !context.hasChanges && !context.autosaveEnabled else {
                throw MCPWriteFailure("OUTCOME_UNCERTAIN", "Saved graph validation requires a clean owned context")
            }
        })
    }
}
#endif
