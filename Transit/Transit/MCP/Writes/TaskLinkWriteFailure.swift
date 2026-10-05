#if os(macOS)
import Foundation

@MainActor enum TaskLinkWriteFailure {
    static func map(_ error: any Error) -> MCPWriteFailure {
        if let failure = error as? MCPWriteFailure { return failure }
        guard let graph = error as? TaskLinkGraphError else { return MCPWriteFailure.from(error) }
        switch graph {
        case .missingSource: return .init("TASK_NOT_FOUND", "Saved source task is unavailable")
        case .ambiguousIdentity: return .init("DUPLICATE_TASK_IDENTIFIER", "Task identity is ambiguous")
        case .revisionConflict: return .init("REVISION_CONFLICT", "Affected endpoint content changed")
        case .repairUnavailable: return .init("LINK_REPAIR_UNAVAILABLE", "Exact selector is unavailable or expired")
        case .invalidOccurrence: return .init("REVISION_CONFLICT", "Exact immutable occurrence evidence changed")
        case .invalidDelta, .endpointPreconditions: return .init("INVALID_INPUT", "Link directives/guards contradict")
        case .invalidGraph: return .init("LINK_GRAPH_INVALID", "Proposed affected graph cannot be certified")
        case .deadlineExceeded, .capacityExceeded:
            return .init("PERSISTENCE_UNAVAILABLE", "Complete saved graph evidence exceeded its operation budget")
        }
    }
}
#endif
