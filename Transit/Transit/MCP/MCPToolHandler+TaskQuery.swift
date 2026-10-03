#if os(macOS)
import Foundation

extension MCPToolHandler {
    func handleQueryTasks(_ args: [String: Any]) -> MCPToolResult {
        do {
            guard taskQueryAdmissionOpen else {
                throw MCPTaskQueryError(code: "QUERY_UNAVAILABLE",
                                        message: "Query unavailable; retry when server is running")
            }
            let request = try MCPTaskQueryRequest.parse(args)
            taskQuerySnapshots.purgeExpired()
            if let cursor = request.cursor { return textResult(try taskQuerySnapshots.page(for: cursor)) }
            let deadline = taskQuerySnapshots.now().advanced(by: .seconds(300))
            let expiry = taskQuerySnapshots.wallNow().addingTimeInterval(300)
            let results = try queryResults(request, args: args)
            return textResult(try encodeQueryPages(results, limit: request.limit, expiry: expiry, deadline: deadline))
        } catch let error as MCPTaskQueryError {
            return queryErrorResult(error)
        } catch {
            return queryErrorResult(MCPTaskQueryError(code: "QUERY_FAILED", message: "Query failed: \(error)"))
        }
    }

    private func queryErrorResult(_ error: MCPTaskQueryError) -> MCPToolResult {
        errorResult(IntentHelpers.encodeJSON(["error": ["code": error.code, "message": error.message]]))
    }

    private func queryResults(_ request: MCPTaskQueryRequest, args: [String: Any]) throws -> [[String: Any]] {
        let formatter = ISO8601DateFormatter()
        switch request.selector {
        case .taskIDs, .displayIDs:
            return try batchQueryResults(request, formatter: formatter)
        case .list, .single:
            guard let filters = try taskQueryFilters(args) else { return [] }
            let tasks: [TransitTask]
            switch request.selector {
            case .single(let displayId):
                do {
                    tasks = [try taskService.findByDisplayID(displayId)]
                } catch TaskService.Error.taskNotFound {
                    return []
                } catch TaskService.Error.duplicateDisplayID {
                    throw MCPTaskQueryError(code: "AMBIGUOUS_TASK_ID",
                                            message: duplicateTaskIdentifierMessage(displayId: displayId))
                } catch {
                    throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Lookup failed: \(error)")
                }
            default:
                do { tasks = try taskFetcher.fetchAllTasks() } catch {
                    throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Failed to fetch tasks: \(error)")
                }
            }
            return try tasks.filter { filters.matches($0) }.sorted { $0.id.uuidString < $1.id.uuidString }
                .map { try queryTaskDictionary($0, request: request, formatter: formatter) }
        }
    }

    private func batchQueryResults(
        _ request: MCPTaskQueryRequest, formatter: ISO8601DateFormatter
    ) throws -> [[String: Any]] {
        let tasks: [TransitTask]
        do { tasks = try taskFetcher.fetchAllTasks() } catch {
            throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Failed to fetch tasks: \(error)")
        }
        let inputs: [(requested: [String: Any], key: String)]
        let index: [String: [TransitTask]]
        switch request.selector {
        case .taskIDs(let ids):
            inputs = ids.map { (["taskId": $0], UUID(uuidString: $0)!.uuidString) }
            index = Dictionary(grouping: tasks) { $0.id.uuidString }
        case .displayIDs(let ids):
            inputs = ids.map { (["displayId": $0], String($0)) }
            index = Dictionary(grouping: tasks.filter { $0.permanentDisplayId != nil }) {
                String($0.permanentDisplayId!)
            }
        default: return []
        }
        var serialized: [UUID: [String: Any]] = [:]
        return try inputs.enumerated().map { position, input in
            var outcome: [String: Any] = ["index": position, "requested": input.requested]
            let matches = index[input.key] ?? []
            if matches.count == 1, let task = matches.first {
                if serialized[task.id] == nil {
                    serialized[task.id] = try queryTaskDictionary(task, request: request, formatter: formatter)
                }
                outcome["task"] = serialized[task.id]
            } else {
                let code = matches.isEmpty ? "TASK_NOT_FOUND" : "AMBIGUOUS_TASK_ID"
                let field = input.requested.keys.first ?? "identifier"
                let identifier = input.requested[field] ?? input.key
                let message = matches.isEmpty ? "No task matches \(field) \(identifier)"
                    : "Multiple tasks match \(field) \(identifier)"
                outcome["error"] = ["code": code, "message": message]
            }
            return outcome
        }
    }

    private func queryTaskDictionary(
        _ task: TransitTask, request: MCPTaskQueryRequest, formatter: ISO8601DateFormatter
    ) throws -> [String: Any] {
        let full = request.detailLevel == "full"
        var comments: [Comment] = []
        if full || request.includeComments {
            do { comments = try commentFetcher.fetchComments(for: task.id) } catch {
                throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Failed to fetch comments: \(error)")
            }
        }
        if full {
            let snapshot = try MCPRecordSnapshot.task(task) { _ in comments }
            var record = snapshot.record
            if !request.includeComments { record.removeValue(forKey: "comments") }
            if let metadata = record["metadata"] as? [String: String], metadata.isEmpty {
                record.removeValue(forKey: "metadata")
            }
            return record
        }
        var dict = IntentHelpers.taskToDict(task, formatter: formatter)
        if request.includeComments {
            dict["comments"] = comments.sorted {
                if $0.creationDate == $1.creationDate { return $0.id.uuidString < $1.id.uuidString }
                return $0.creationDate < $1.creationDate
            }.map { [
                "id": $0.id.uuidString, "authorName": $0.authorName, "content": $0.content,
                "isAgent": $0.isAgent, "creationDate": formatter.string(from: $0.creationDate)
            ] as [String: Any] }
        }
        return dict
    }

    func encodeQueryPages(
        _ results: [[String: Any]], limit: Int, expiry: Date, deadline: ContinuousClock.Instant
    ) throws -> String {
        let count = max(1, (results.count + limit - 1) / limit)
        let cursors = (0..<(count - 1)).map { _ in taskQuerySnapshots.makeCursor() }
        let expiryText = ISO8601DateFormatter().string(from: expiry)
        var pages: [String] = []
        var bytes = 0
        for position in 0..<count {
            let start = position * limit
            let end = min(start + limit, results.count)
            let next: Any = position < cursors.count ? cursors[position] : NSNull()
            let payload: [String: Any] = ["results": Array(results[start..<end]),
                                          "nextCursor": next, "expiresAt": expiryText]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            bytes += data.count
            guard bytes <= taskQuerySnapshots.maxBytes else { throw taskQuerySnapshots.capacityError() }
            guard let text = String(data: data, encoding: .utf8) else {
                throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Could not encode query page")
            }
            pages.append(text)
        }
        try taskQuerySnapshots.publish(pages: pages, cursors: cursors, deadline: deadline)
        return pages[0]
    }

    private func projectQueryError(_ error: ProjectLookupError) -> MCPTaskQueryError {
        let code: String
        switch error {
        case .storageFailure: code = "QUERY_FAILED"
        case .ambiguous: code = "AMBIGUOUS_FILTER"
        default: code = "INVALID_INPUT"
        }
        return MCPTaskQueryError(code: code, message: IntentHelpers.mapProjectLookupError(error).hint)
    }

    // Preserve the established validation order and filter precedence.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func taskQueryFilters(_ args: [String: Any]) throws -> MCPQueryFilters? {
        // Reject malformed or non-string projectId when the key is present
        // [T-665, T-788].
        let parsedProjectId: UUID?
        switch parseProjectIdArgument(args) {
        case .failure(.message(let message)): throw MCPTaskQueryError.invalid(message)
        case .success(let parsed): parsedProjectId = parsed
        }
        // Reject non-string `project` filter [T-1116].
        if args["project"] != nil, !(args["project"] is String) {
            throw MCPTaskQueryError.invalid("project must be a string")
        }
        // Resolve a valid project ID to an existing project before filtering [T-1783].
        var projectFilter: UUID?
        var resolvedProject: Project?
        if let pid = parsedProjectId {
            // A valid UUID is still an invalid project filter when no matching
            // project exists. Resolve it before applying the in-memory filter so
            // MCP matches the project-name and QueryTasksIntent contracts.
            switch projectService.findProject(id: pid) {
            case .success(let found):
                resolvedProject = found
                projectFilter = found.id
            case .failure(let err): throw projectQueryError(err)
            }
        } else if let name = args["project"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch projectService.findProject(id: nil, name: name) {
            case .success(let found):
                resolvedProject = found
                projectFilter = found.id
            case .failure(let err): throw projectQueryError(err)
            }
        }

        // Validate every remaining filter before resolving a milestone. A no-match or
        // storage failure must not let a malformed filter look like a valid empty result.
        // This also preserves validation when displayId would otherwise return early. [T-1608]
        // Reject non-integer milestoneDisplayId when key is present [T-613].
        if args["milestoneDisplayId"] != nil, IntentHelpers.parseIntValue(args["milestoneDisplayId"]) == nil {
            throw MCPTaskQueryError.invalid("milestoneDisplayId must be an integer")
        }
        // Reject non-string `milestone` name filter [T-1266]. Without this guard a
        // numeric/boolean/array milestone falls through the `as? String` cast below
        // to the "no milestone filter" branch, returning every task unfiltered.
        if args["milestone"] != nil, !(args["milestone"] is String) {
            throw MCPTaskQueryError.invalid("milestone must be a string")
        }
        // Validate enum filters before building MCPQueryFilters [T-732].
        if let error = validateEnumFilter(args, key: "status", type: TaskStatus.self) {
            throw MCPTaskQueryError.invalid(error.content.first?.text ?? "Invalid filter")
        }
        if let error = validateEnumFilter(args, key: "not_status", type: TaskStatus.self) {
            throw MCPTaskQueryError.invalid(error.content.first?.text ?? "Invalid filter")
        }
        // type is a single-value filter (schema declares a string enum; read back as
        // args["type"] as? String). Reject arrays so they aren't silently dropped. [T-1404]
        if let error = validateEnumFilter(args, key: "type", type: TaskType.self, allowArray: false) {
            throw MCPTaskQueryError.invalid(error.content.first?.text ?? "Invalid filter")
        }
        // priority is a multi-value filter (schema declares an array, mirroring status).
        if let error = validateEnumFilter(args, key: "priority", type: TaskPriority.self, allowArray: true) {
            throw MCPTaskQueryError.invalid(error.content.first?.text ?? "Invalid filter")
        }
        // Reject a present-but-non-boolean `unfinished` flag [T-1095]. A plain
        // `as? Bool` would silently coerce "true"/1/null to false, returning
        // done/abandoned tasks even though the caller requested unfinished-only.
        if let unfinishedArg = args["unfinished"], IntentHelpers.parseBoolValue(unfinishedArg) == nil {
            throw MCPTaskQueryError.invalid("unfinished must be a boolean")
        }
        // Reject non-string `search` filter [T-1156]. A present non-string value must not be
        // silently dropped by `as? String`, which would broaden results instead of erroring.
        if args["search"] != nil, !(args["search"] is String) {
            throw MCPTaskQueryError.invalid("search must be a string")
        }
        // Reject non-integer displayId before a milestone no-match or failure can return early [T-634].
        if args["displayId"] != nil, IntentHelpers.parseIntValue(args["displayId"]) == nil {
            throw MCPTaskQueryError.invalid("displayId must be an integer")
        }

        // Resolve milestone filter.
        var milestoneFilter: Set<UUID>?
        if let milestoneDisplayId = IntentHelpers.parseIntValue(args["milestoneDisplayId"]) {
            do {
                milestoneFilter = [try milestoneDisplayIDFinder.findByDisplayID(milestoneDisplayId).id]
            } catch MilestoneService.Error.milestoneNotFound {
                return nil
            } catch MilestoneService.Error.duplicateDisplayID {
                throw MCPTaskQueryError(
                    code: "AMBIGUOUS_FILTER",
                    message: "Duplicate milestone identifier detected for displayId \(milestoneDisplayId)"
                )
            } catch {
                throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Failed to look up milestone: \(error)")
            }
        } else if let milestoneName = args["milestone"] as? String,
                  !milestoneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let projectFilter {
                // Scoped to a single project — at most one milestone matches.
                guard let project = resolvedProject else {
                    return nil
                }
                do {
                    guard let milestone = try milestoneService.findByName(milestoneName, in: project) else {
                        return nil
                    }
                    milestoneFilter = [milestone.id]
                } catch MilestoneService.Error.ambiguousName {
                    throw MCPTaskQueryError(code: "AMBIGUOUS_FILTER", message:
                        "Multiple milestones named '\(milestoneName)' exist in project '\(project.name)'"
                    )
                } catch {
                    throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Failed to look up milestone: \(error)")
                }
            } else {
                // No project filter — collect ALL milestones with this name across projects.
                // A storage failure must remain distinct from a valid no-match response. [T-1608]
                let allMilestones: [Milestone]
                do {
                    allMilestones = try milestoneFetcher.fetchAllMilestones()
                } catch {
                    throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Failed to fetch milestones: \(error)")
                }
                let matchingIds = Set(
                    allMilestones
                        .filter {
                            MilestoneNamePolicy.normalized($0.name)
                                == MilestoneNamePolicy.normalized(milestoneName)
                        }
                        .map(\.id)
                )
                if matchingIds.isEmpty {
                    return nil
                }
                milestoneFilter = matchingIds
            }
        }

        let search = (args["search"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filters = MCPQueryFilters.from(
            args: args, type: args["type"] as? String, projectId: projectFilter,
            search: search?.isEmpty == true ? nil : search,
            milestoneIds: milestoneFilter
        )

        return filters
    }
}
#endif
