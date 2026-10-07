#if os(macOS)
import Foundation
import SwiftData

/// Installs both halves against existing app owners; listener restarts do not create authority.
@MainActor struct MCPConsolidationAppCapability {
    let previews: MCPConsolidationPreviewAdapter
    let writes: MCPConsolidationWriteAdapter

    init?(container: ModelContainer, reads: MCPReadService, coordinator: MCPWriteCoordinator,
          taskAllocator: DisplayIDAllocator, milestoneAllocator: DisplayIDAllocator) {
        guard let scope = coordinator.localScopeId else { return nil }
        let source = ConsolidationRetainedReviewSource(container: container, store: reads.snapshots,
            originScopeId: scope)
        previews = MCPConsolidationPreviewAdapter(service: reads, originScopeId: scope)
        writes = MCPConsolidationWriteAdapter(taskAllocator: taskAllocator, milestoneAllocator: milestoneAllocator,
            configuration: TaskConsolidationService.Configuration(originScopeId: scope, reviewSource: { id, context in
                try source.resolve(id, in: context)
            }))
    }
}
#endif
