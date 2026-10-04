#if os(macOS)
import Foundation

@MainActor enum MCPBatchTaskContext {
    static func normal(_ request: MCPBatchTaskRequest, recovery: MCPMutationRecoveryContext?) -> MCPResultContext {
        MCPResultContext(tool: "mutate_tasks", semanticFailure: nil, mutationRecovery: recovery,
            entityPositions: request.items.map {
                .init(entityType: .task, sourcePath: "/items/\($0.index)/taskId")
            })
    }
}
#endif
