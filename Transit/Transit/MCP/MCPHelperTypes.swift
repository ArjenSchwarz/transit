#if os(macOS)
import Foundation

// MARK: - Query Filters

struct MCPQueryFilters {
    let statuses: [String]?
    let notStatuses: [String]?
    let type: String?
    let projectId: UUID?

    /// Build filters from raw MCP arguments (status parsing + unfinished flag resolution).
    static func from(args: [String: Any], type: String?, projectId: UUID?) -> MCPQueryFilters {
        // Accept single string (backward compat) or array
        let statuses: [String]?
        if let array = args["status"] as? [String] {
            statuses = array
        } else if let single = args["status"] as? String {
            statuses = [single]
        } else {
            statuses = nil
        }

        let notStatusesArg = args["not_status"] as? [String]
        let unfinished = args["unfinished"] as? Bool ?? false
        let resolvedNotStatuses: [String]?
        if unfinished {
            let terminal = [TaskStatus.done.rawValue, TaskStatus.abandoned.rawValue]
            resolvedNotStatuses = Array(Set(terminal).union(notStatusesArg ?? []))
        } else {
            resolvedNotStatuses = notStatusesArg
        }

        return MCPQueryFilters(
            statuses: statuses, notStatuses: resolvedNotStatuses,
            type: type, projectId: projectId
        )
    }

    func matches(_ task: TransitTask) -> Bool {
        if let statuses, !statuses.isEmpty, !statuses.contains(task.statusRawValue) { return false }
        if let notStatuses, !notStatuses.isEmpty, notStatuses.contains(task.statusRawValue) { return false }
        if let type, task.typeRawValue != type { return false }
        if let projectId, task.project?.id != projectId { return false }
        return true
    }
}

nonisolated struct EmptyResult: Encodable, Sendable {}

#endif
