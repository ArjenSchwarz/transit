#if os(macOS)
import Foundation

// MARK: - Query Filters

struct MCPQueryFilters {
    let statuses: [String]?
    let notStatuses: [String]?
    let type: String?
    let projectId: UUID?
    let search: String?
    let milestoneId: UUID?

    /// Build filters from raw MCP arguments (status parsing + unfinished flag resolution).
    ///
    /// `type`, `projectId`, and `milestoneId` are pre-parsed by the caller (`handleQueryTasks`)
    /// because they involve complex logic (UUID validation, project name lookup with error handling).
    /// This factory only handles status-related parsing from the raw args dict.
    static func from(
        args: [String: Any],
        type: String?,
        projectId: UUID?,
        search: String? = nil,
        milestoneId: UUID? = nil
    ) -> MCPQueryFilters {
        // The schema declares status/not_status as type "array", but we defensively accept
        // a single string for backward compatibility with callers that don't wrap in an array.
        let statuses: [String]?
        if let array = args["status"] as? [String] {
            statuses = array
        } else if let single = args["status"] as? String {
            statuses = [single]
        } else {
            statuses = nil
        }

        let notStatusesArg: [String]?
        if let array = args["not_status"] as? [String] {
            notStatusesArg = array
        } else if let single = args["not_status"] as? String {
            notStatusesArg = [single]
        } else {
            notStatusesArg = nil
        }
        let unfinished = args["unfinished"] as? Bool ?? false
        let resolvedNotStatuses: [String]?
        if unfinished {
            let terminal = [TaskStatus.done.rawValue, TaskStatus.abandoned.rawValue]
            let extra = (notStatusesArg ?? []).filter { !terminal.contains($0) }
            resolvedNotStatuses = terminal + extra
        } else {
            resolvedNotStatuses = notStatusesArg
        }

        return MCPQueryFilters(
            statuses: statuses, notStatuses: resolvedNotStatuses,
            type: type, projectId: projectId, search: search, milestoneId: milestoneId
        )
    }

    func matches(_ task: TransitTask) -> Bool {
        if let statuses, !statuses.isEmpty, !statuses.contains(task.statusRawValue) { return false }
        if let notStatuses, !notStatuses.isEmpty, notStatuses.contains(task.statusRawValue) { return false }
        if let type, task.typeRawValue != type { return false }
        if let projectId, task.project?.id != projectId { return false }
        if let milestoneId, task.milestone?.id != milestoneId { return false }
        if let search, !search.isEmpty {
            let nameMatch = task.name.localizedCaseInsensitiveContains(search)
            let descMatch = task.taskDescription?.localizedCaseInsensitiveContains(search) ?? false
            if !nameMatch && !descMatch { return false }
        }
        return true
    }
}

nonisolated struct EmptyResult: Encodable, Sendable {}

#endif
