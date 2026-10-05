#if os(macOS)
import Foundation

/// Pure projection of a saved value capture. No service lookup, fetch, save or publication.
enum MCPReadProjection {
    static func tasks(_ view: CapturedReadView, request: MCPTaskQueryRequest,
                      arguments: [String: Any],
                      budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws -> [[String: Any]] {
        let available = scopedTasks(view)
        switch request.selector {
        case .taskIDs(let ids):
            return try batch(view, request: request, inputs: ids.map {
                (["taskId": $0], UUID(uuidString: $0)!.uuidString)
            },
                             index: Dictionary(grouping: available) { $0.id.uuidString }, budget: budget)
        case .displayIDs(let ids):
            return try batch(view, request: request, inputs: ids.map { (["displayId": $0], String($0)) },
                index: Dictionary(grouping: available.filter { $0.permanentDisplayId != nil }) {
                    String($0.permanentDisplayId!)
                }, budget: budget)
        case .list, .single:
            guard let filters = try filters(arguments, view: view) else { return [] }
            let selected = try taskBodyKeys(available.map(selectionValue), request: request, filters: filters)
            let keys = try Set(available.filter { task in
                try budget.check()
                guard selected.contains(task.physicalKey) else { return false }
                return try request.graphOptions?.matches(task.id, graph: view.taskLinkGraph, budget: budget) ?? true
            }.map(\.physicalKey))
            return try available.filter { keys.contains($0.physicalKey) }
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { try task($0, view: view, request: request, budget: budget) }
        }
    }

    private static func scopedTasks(_ view: CapturedReadView) -> [ReadTask] {
        guard case .projects(let keys) = view.captureScope else { return view.tasks }
        let projects = Set(keys)
        return view.tasks.filter { $0.projectKey.map { projects.contains($0) } == true }
    }

    private static func batch(_ view: CapturedReadView, request: MCPTaskQueryRequest,
                              inputs: [(requested: [String: Any], key: String)],
                              index: [String: [ReadTask]], budget: TaskLinkGraphBudget) throws -> [[String: Any]] {
        var serialized: [LocalRecordKey: [String: Any]] = [:]
        return try inputs.enumerated().map { position, input in
            try budget.check()
            var outcome: [String: Any] = ["index": position, "requested": input.requested]
            let matches = index[input.key] ?? []
            if matches.count == 1, let record = matches.first {
                if serialized[record.physicalKey] == nil {
                    serialized[record.physicalKey] = try task(record, view: view, request: request, budget: budget)
                }
                outcome["task"] = serialized[record.physicalKey]
            } else {
                let field = input.requested.keys.first ?? "identifier"
                let identifier = input.requested[field] ?? input.key
                outcome["error"] = ["code": matches.isEmpty ? "TASK_NOT_FOUND" : "AMBIGUOUS_TASK_ID",
                    "message": matches.isEmpty ? "No task matches \(field) \(identifier)"
                        : "Multiple tasks match \(field) \(identifier)"]
            }
            return outcome
        }
    }

    static func task(_ task: ReadTask, view: CapturedReadView,
                     request: MCPTaskQueryRequest,
                     budget: TaskLinkGraphBudget = TaskLinkGraphBudget()) throws -> [String: Any] {
        if request.detailLevel == "full" {
            guard task.revision != nil, let bytes = task.fullRecordWithoutCommentsJSON else {
                throw MCPReadCaptureError.incoherentCapture
            }
            var record = try object(bytes)
            if request.includeComments {
                // Canonical r1 covers UUID-based comments, including duplicate physical owners.
                guard let comments = task.requestedCommentRecordsJSON else {
                    throw MCPReadCaptureError.incoherentCapture
                }
                record["comments"] = try JSONSerialization.jsonObject(with: comments)
            }
            let detail = try TaskLinkQueryProjection.detail(task.id, graph: view.taskLinkGraph, budget: budget)
            record.merge(detail) { _, new in new }
            if (record["metadata"] as? [String: String])?.isEmpty == true { record.removeValue(forKey: "metadata") }
            return record
        }
        let formatter = ISO8601DateFormatter()
        var record: [String: Any] = ["taskId": task.id.uuidString, "name": task.name,
            "status": task.rawStatus, "type": task.rawType, "priority": task.effectivePriority,
            "lastStatusChangeDate": formatter.string(from: task.lastStatusChangeDate)]
        record["displayId"] = task.permanentDisplayId
        if let project = view.projects.first(where: { $0.physicalKey == task.projectKey }) {
            record["projectId"] = project.id.uuidString
            record["projectName"] = project.name
        }
        if let date = task.completionDate { record["completionDate"] = formatter.string(from: date) }
        if let milestone = view.milestones.first(where: { $0.physicalKey == task.milestoneKey }) {
            var info: [String: Any] = ["milestoneId": milestone.id.uuidString, "name": milestone.name]
            info["displayId"] = milestone.permanentDisplayId
            record["milestone"] = info
        }
        if request.includeComments {
            record["comments"] = view.comments.filter { $0.storedTaskID == task.id }.sorted {
                ($0.creationDate, $0.id.uuidString) < ($1.creationDate, $1.id.uuidString)
            }.map { ["id": $0.id.uuidString, "authorName": $0.authorName, "content": $0.content,
                     "isAgent": $0.isAgent, "creationDate": formatter.string(from: $0.creationDate)] as [String: Any] }
        }
        return record
    }

    static func object(_ bytes: Data) throws -> [String: Any] {
        do {
            guard let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                throw MCPReadCaptureError.serializationFailure
            }
            return value
        } catch { throw MCPReadCaptureError.serializationFailure }
    }

    static func project(_ args: [String: Any], view: CapturedReadView,
                        validateIgnoredName: Bool = true) throws -> ReadProject? {
        let identities = view.projects.map { ReadProjectIdentity(id: $0.id, name: $0.name) }
        guard let identity = try projectIdentity(args, projects: identities,
                                                validateIgnoredName: validateIgnoredName) else { return nil }
        return view.projects.first { $0.id == identity.id && $0.name == identity.name }
    }

    static func projectIdentity(_ args: [String: Any], projects: [ReadProjectIdentity],
                                validateIgnoredName: Bool = true) throws -> ReadProjectIdentity? {
        let id: UUID?
        if let raw = args["projectId"] {
            guard let text = raw as? String, let parsed = UUID(uuidString: text) else {
                throw MCPTaskQueryError.invalid("Invalid projectId: expected a UUID string")
            }
            id = parsed
        } else { id = nil }
        if id == nil || validateIgnoredName, args["project"] != nil, !(args["project"] is String) {
            throw MCPTaskQueryError.invalid("project must be a string")
        }
        let name = (args["project"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id != nil || name?.isEmpty == false else { return nil }
        let matches = projects.filter {
            if let id { return $0.id == id }
            return ProjectNamePolicy.normalized($0.name) == ProjectNamePolicy.normalized(name!)
        }
        guard let project = matches.first else {
            let hint = id.map { "No project with ID \($0.uuidString)" } ?? "No project named \"\(name!)\""
            throw MCPTaskQueryError.invalid(hint)
        }
        guard id != nil || matches.count == 1 else {
            throw MCPTaskQueryError(code: "AMBIGUOUS_FILTER",
                                    message: "\(matches.count) projects match \"\(name ?? "")\"")
        }
        return project
    }

    // Keep project resolution before remaining-filter validation and milestone resolution afterwards.
    static func filters(_ args: [String: Any], view: CapturedReadView) throws -> MCPQueryFilters? {
        let project = try project(args, view: view)
        try validateTaskScalars(args)
        return try taskFilters(args, project: project.map { ReadProjectIdentity(id: $0.id, name: $0.name) },
            milestones: view.milestones.map { ReadMilestoneIdentity(id: $0.id,
                permanentDisplayId: $0.permanentDisplayId, name: $0.name, storedProjectID: $0.storedProjectID,
                rawStatus: $0.rawStatus, milestoneDescription: $0.milestoneDescription) })
    }

    static func taskFilters(_ args: [String: Any], project: ReadProjectIdentity?,
                            milestones: [ReadMilestoneIdentity]) throws -> MCPQueryFilters? {
        let milestoneIDs: Set<UUID>?
        switch try milestoneFilter(args, project: project, milestones: milestones) {
        case .noFilter: milestoneIDs = nil
        case .matched(let ids): milestoneIDs = ids
        case .noMatch: return nil
        }
        let search = (args["search"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MCPQueryFilters.from(args: args, type: args["type"] as? String, projectId: project?.id,
                                   search: search?.isEmpty == true ? nil : search, milestoneIds: milestoneIDs)
    }

    enum MilestoneFilter {
        case noFilter, matched(Set<UUID>), noMatch
    }

    static func milestoneFilter(_ args: [String: Any], project: ReadProjectIdentity?,
                                milestones: [ReadMilestoneIdentity]) throws -> MilestoneFilter {
        if let id = IntentHelpers.parseIntValue(args["milestoneDisplayId"]) {
            let matches = milestones.filter { $0.permanentDisplayId == id }
            guard matches.count <= 1 else {
                throw MCPTaskQueryError(code: "AMBIGUOUS_FILTER",
                    message: "Duplicate milestone identifier detected for displayId \(id)")
            }
            guard let match = matches.first else { return .noMatch }
            return .matched([match.id])
        }
        if let name = args["milestone"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matches = milestones.filter {
                (project == nil || $0.storedProjectID == project?.id)
                    && MilestoneNamePolicy.normalized($0.name) == MilestoneNamePolicy.normalized(name)
            }
            if let project, matches.count > 1 {
                throw MCPTaskQueryError(code: "AMBIGUOUS_FILTER",
                    message: "Multiple milestones named '\(name)' exist in project '\(project.name)'")
            }
            return matches.isEmpty ? .noMatch : .matched(Set(matches.map(\.id)))
        }
        return .noFilter
    }

    static func validateTaskScalars(_ args: [String: Any]) throws {
        try integer(args, key: "milestoneDisplayId")
        try string(args, key: "milestone")
        try enumeration(args, key: "status", type: TaskStatus.self)
        try enumeration(args, key: "not_status", type: TaskStatus.self)
        try enumeration(args, key: "type", type: TaskType.self, allowArray: false)
        try enumeration(args, key: "priority", type: TaskPriority.self)
        if let value = args["unfinished"], IntentHelpers.parseBoolValue(value) == nil {
            throw MCPTaskQueryError.invalid("unfinished must be a boolean")
        }
        try string(args, key: "search")
        try integer(args, key: "displayId")
    }

    private static func matches(_ task: ReadTask, filters: MCPQueryFilters) -> Bool {
        matches(selectionValue(task), filters: filters)
    }

    static func selectionValue(_ task: ReadTask) -> ReadTaskSelectionValue {
        ReadTaskSelectionValue(physicalKey: task.physicalKey, id: task.id, permanentDisplayId: task.permanentDisplayId,
            name: task.name, taskDescription: task.taskDescription, storedProjectID: task.storedProjectID,
            storedMilestoneID: task.storedMilestoneID, rawStatus: task.rawStatus, rawType: task.rawType,
            effectivePriority: task.effectivePriority)
    }

    static func matches(_ task: ReadTaskSelectionValue, filters: MCPQueryFilters) -> Bool {
        if let values = filters.statuses, !values.isEmpty, !values.contains(task.rawStatus) { return false }
        if let values = filters.notStatuses, !values.isEmpty, values.contains(task.rawStatus) { return false }
        if let type = filters.type, type != task.rawType { return false }
        if let values = filters.priorities, !values.isEmpty, !values.contains(task.effectivePriority) { return false }
        if let id = filters.projectId, id != task.storedProjectID { return false }
        if let ids = filters.milestoneIds, !ids.isEmpty,
           task.storedMilestoneID.map({ ids.contains($0) }) != true { return false }
        if let search = filters.search, !search.isEmpty,
           !task.name.localizedCaseInsensitiveContains(search),
           task.taskDescription?.localizedCaseInsensitiveContains(search) != true { return false }
        return true
    }

    static func integer(_ args: [String: Any], key: String) throws {
        if args[key] != nil, IntentHelpers.parseIntValue(args[key]) == nil {
            throw MCPTaskQueryError.invalid("\(key) must be an integer")
        }
    }

    static func string(_ args: [String: Any], key: String) throws {
        if args[key] != nil, !(args[key] is String) { throw MCPTaskQueryError.invalid("\(key) must be a string") }
    }

    static func enumeration<E: RawRepresentable & CaseIterable>(
        _ args: [String: Any], key: String, type: E.Type, allowArray: Bool = true
    ) throws where E.RawValue == String {
        guard let raw = args[key] else { return }
        let expectation = allowArray ? "a string or array of strings" : "a string"
        let values: [String]
        if let single = raw as? String { values = [single] } else if allowArray, let array = raw as? [String] {
            values = array
        } else { throw MCPTaskQueryError.invalid("Invalid \(key): expected \(expectation)") }
        let all = E.allCases.map(\.rawValue)
        let invalid = values.filter { !all.contains($0) }
        if !invalid.isEmpty {
            let message = "Invalid \(key): \(invalid.joined(separator: ", ")). "
                + "Must be one of: \(all.joined(separator: ", "))"
            throw MCPTaskQueryError.invalid(message)
        }
    }
}
#endif
