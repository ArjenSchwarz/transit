#if os(macOS)
import Foundation

// MARK: - Query Filters

struct MCPQueryFilters {
    let status: String?
    let type: String?
    let projectId: UUID?

    func matches(_ task: TransitTask) -> Bool {
        if let status, task.statusRawValue != status { return false }
        if let type, task.typeRawValue != type { return false }
        if let projectId, task.project?.id != projectId { return false }
        return true
    }
}

nonisolated struct EmptyResult: Encodable, Sendable {}

#endif
