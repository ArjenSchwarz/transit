import AppIntents
import Foundation

private struct DateRangeFilter: Codable {
    var relative: String?
    var from: String?
    var toDate: String?

    enum CodingKeys: String, CodingKey {
        case relative
        case from
        case toDate = "to"
    }

    init(relative: String? = nil, from: String? = nil, toDate: String? = nil) {
        self.relative = relative
        self.from = from
        self.toDate = toDate
    }
}

private struct QueryFilters: Codable {
    var displayId: Int?
    var status: String?
    var type: String?
    var priority: String?
    var projectId: String?
    var search: String?
    var completionDate: DateRangeFilter?
    var lastStatusChangeDate: DateRangeFilter?
    var milestone: String?
    var milestoneDisplayId: Int?

    init(
        displayId: Int? = nil,
        status: String? = nil,
        type: String? = nil,
        priority: String? = nil,
        projectId: String? = nil,
        search: String? = nil,
        completionDate: DateRangeFilter? = nil,
        lastStatusChangeDate: DateRangeFilter? = nil,
        milestone: String? = nil,
        milestoneDisplayId: Int? = nil
    ) {
        self.displayId = displayId
        self.status = status
        self.type = type
        self.priority = priority
        self.projectId = projectId
        self.search = search
        self.completionDate = completionDate
        self.lastStatusChangeDate = lastStatusChangeDate
        self.milestone = milestone
        self.milestoneDisplayId = milestoneDisplayId
    }
}

/// Queries tasks with optional filters via JSON input. Exposed as "Transit: Query Tasks"
/// in Shortcuts. [req 18.1-18.5]
struct QueryTasksIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Query Tasks"

    nonisolated(unsafe) static var description = IntentDescription(
        "Search and filter tasks. Pass an empty string or {} to return all tasks.",
        categoryName: "Tasks",
        resultValueName: "Tasks JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Input JSON",
        description: """
        JSON object with optional filters: "displayId" (integer, for single-task lookup with detailed output \
        including description and metadata), "status" (idea | planning | spec | ready-for-implementation | \
        in-progress | ready-for-review | done | abandoned), "type" (bug | feature | chore | research | \
        documentation), "priority" (low | medium | high), "projectId" (UUID), \
        "search" (case-insensitive substring match on name and description), \
        "milestone" (name), "milestoneDisplayId" (integer), "completionDate", "lastStatusChangeDate". \
        Date filters accept {"relative":"today|this-week|this-month"} or {"from":"YYYY-MM-DD","to":"YYYY-MM-DD"} \
        (from/to optional and inclusive; relative takes precedence if both are present). \
        All filters are optional. Example: {"displayId":42} or {"status":"in-progress"} or \
        {"search":"login bug"} or {"milestoneDisplayId":1}.
        """
    )
    var input: String

    @Dependency
    private var projectService: ProjectService

    @Dependency
    private var taskService: TaskService

    @Dependency
    private var milestoneService: MilestoneService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = QueryTasksIntent.execute(
            input: input,
            projectService: projectService,
            taskService: taskService,
            milestoneService: milestoneService
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    /// Outcome of resolving an optional `milestoneDisplayId` filter:
    /// - `.unfiltered` when no milestone display ID was supplied;
    /// - `.resolved(id)` when exactly one milestone matches;
    /// - `.notFound` when no milestone matches (caller should return an empty result);
    /// - `.error` when the lookup fails (e.g. duplicate display IDs from CloudKit sync).
    private enum MilestoneDisplayIdResolution {
        case unfiltered
        case resolved(UUID)
        case notFound
        case error(IntentError)
    }

    @MainActor
    static func execute(
        input: String,
        projectService: ProjectService,
        taskService: TaskService,
        milestoneService: MilestoneService
    ) -> String {
        switch parseInput(input) {
        case .failure(let error):
            return error.json
        case .success(let filters):
            return execute(
                filters: filters,
                projectService: projectService,
                taskService: taskService,
                milestoneService: milestoneService
            )
        }
    }

    @MainActor
    private static func execute(
        filters: QueryFilters,
        projectService: ProjectService,
        taskService: TaskService,
        milestoneService: MilestoneService
    ) -> String {

        // Validate projectId, enum, and date filters if present
        if let error = validateFilters(filters, projectService: projectService) {
            return error.json
        }

        // Resolve milestoneDisplayId via MilestoneService so duplicate display IDs (from
        // CloudKit sync conflicts) surface as INTERNAL_ERROR instead of silently mixing
        // tasks from multiple milestones. [T-1146]
        let resolvedMilestoneId: UUID?
        switch resolveMilestoneDisplayIdFilter(filters, milestoneService: milestoneService) {
        case .unfiltered:
            resolvedMilestoneId = nil
        case .resolved(let id):
            resolvedMilestoneId = id
        case .notFound:
            return IntentHelpers.encodeJSONArray([])
        case .error(let intentError):
            return intentError.json
        }

        // Single-task lookup by displayId. Surface CloudKit duplicate-id corruption
        // as an INTERNAL_ERROR instead of letting `try?` collapse it into an empty
        // "not found" result.
        if let displayId = filters.displayId {
            do {
                let task = try taskService.findByDisplayID(displayId)
                let filtered = applyFilters(filters, to: [task], resolvedMilestoneId: resolvedMilestoneId)
                let formatter = ISO8601DateFormatter()
                return IntentHelpers.encodeJSONArray(filtered.map {
                    IntentHelpers.taskToDict($0, formatter: formatter, detailed: true)
                })
            } catch TaskService.Error.duplicateDisplayID {
                return IntentError.internalError(
                    hint: "Duplicate task identifier for displayId \(displayId)"
                ).json
            } catch {
                return IntentHelpers.encodeJSONArray([])
            }
        }

        let allTasks = (try? taskService.fetchAllTasks()) ?? []
        let filtered = applyFilters(filters, to: allTasks, resolvedMilestoneId: resolvedMilestoneId)
        let formatter = ISO8601DateFormatter()
        return IntentHelpers.encodeJSONArray(filtered.map {
            IntentHelpers.taskToDict($0, formatter: formatter)
        })
    }

    // MARK: - Private Helpers

    /// Parses the input JSON into `QueryFilters`, rejecting any filter key whose value is
    /// an explicit JSON `null`. `JSONDecoder`'s synthesized `decodeIfPresent` cannot tell a
    /// present-but-null value from an omitted key, so we inspect the raw object separately
    /// for `NSNull` values before decoding. This matches the presence-vs-validity validation
    /// used by the MCP/JSONSerialization paths.
    @MainActor private static func parseInput(_ input: String) -> Result<QueryFilters, IntentError> {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .success(QueryFilters())
        }
        guard let data = input.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.invalidInput(hint: "Expected valid JSON object"))
        }
        if let nullKey = object.first(where: { $0.value is NSNull })?.key {
            return .failure(.invalidInput(hint: "Filter \"\(nullKey)\" must not be null"))
        }
        guard let filters = try? JSONDecoder().decode(QueryFilters.self, from: data) else {
            return .failure(.invalidInput(hint: "Expected valid JSON object"))
        }
        return .success(filters)
    }

    /// Runs all pre-lookup filter validations, returning the first error encountered.
    @MainActor private static func validateFilters(
        _ filters: QueryFilters,
        projectService: ProjectService
    ) -> IntentError? {
        validateProjectFilter(filters, projectService: projectService)
            ?? validateEnumFilters(filters)
            ?? validateDateFilters(filters)
    }

    @MainActor private static func validateProjectFilter(
        _ filters: QueryFilters,
        projectService: ProjectService
    ) -> IntentError? {
        guard let idString = filters.projectId else { return nil }
        guard let projectId = UUID(uuidString: idString) else {
            return .invalidInput(hint: "Invalid projectId format")
        }
        if case .failure = projectService.findProject(id: projectId) {
            return .projectNotFound(hint: "No project with ID \(idString)")
        }
        return nil
    }

    @MainActor private static func validateEnumFilters(_ filters: QueryFilters) -> IntentError? {
        if let status = filters.status, TaskStatus(rawValue: status) == nil {
            return .invalidStatus(hint: "Unknown status: \(status)")
        }
        if let type = filters.type, TaskType(rawValue: type) == nil {
            return .invalidType(hint: "Unknown type: \(type)")
        }
        if let priority = filters.priority, TaskPriority(rawValue: priority) == nil {
            return .invalidPriority(hint: "Unknown priority: \(priority)")
        }
        return nil
    }

    @MainActor private static func validateDateFilters(_ filters: QueryFilters) -> IntentError? {
        if let completionDate = filters.completionDate,
           dateRange(from: completionDate) == nil {
            return .invalidInput(hint: "Invalid completionDate filter format")
        }
        if let lastStatusChangeDate = filters.lastStatusChangeDate,
           dateRange(from: lastStatusChangeDate) == nil {
            return .invalidInput(hint: "Invalid lastStatusChangeDate filter format")
        }
        return nil
    }

    @MainActor private static func applyFilters(
        _ filters: QueryFilters,
        to tasks: [TransitTask],
        resolvedMilestoneId: UUID?
    ) -> [TransitTask] {
        let completionRange = filters.completionDate.flatMap(dateRange)
        let lastStatusChangeRange = filters.lastStatusChangeDate.flatMap(dateRange)
        let projectId = filters.projectId.flatMap(UUID.init)
        let searchText = filters.search?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSearch = (searchText?.isEmpty == true) ? nil : searchText

        var result: [TransitTask] = []
        result.reserveCapacity(tasks.count)

        for task in tasks {
            if let status = filters.status, task.statusRawValue != status {
                continue
            }
            if let projectId, task.project?.id != projectId {
                continue
            }
            if let type = filters.type, task.typeRawValue != type {
                continue
            }
            // Effective-priority invariant (Req 1.4): compare the computed accessor so a
            // legacy task with no stored priority matches a "medium" filter.
            if let priority = filters.priority, task.priority.rawValue != priority {
                continue
            }
            if let search = effectiveSearch {
                let nameMatch = task.name.localizedCaseInsensitiveContains(search)
                let descMatch = task.taskDescription?.localizedCaseInsensitiveContains(search) ?? false
                if !nameMatch && !descMatch { continue }
            }
            if !matchesDateFilter(task.completionDate, range: completionRange) { continue }
            if !matchesDateFilter(task.lastStatusChangeDate, range: lastStatusChangeRange) { continue }
            if !matchesMilestoneFilter(task, filters: filters, resolvedMilestoneId: resolvedMilestoneId) {
                continue
            }
            result.append(task)
        }
        return result
    }

    @MainActor private static func matchesDateFilter(_ date: Date?, range: DateFilterHelpers.DateRange?) -> Bool {
        guard let range else { return true }
        guard let date else { return false }
        return DateFilterHelpers.dateInRange(date, range: range)
    }

    @MainActor private static func matchesMilestoneFilter(
        _ task: TransitTask, filters: QueryFilters, resolvedMilestoneId: UUID?
    ) -> Bool {
        // When a milestoneDisplayId was supplied, match on the resolved UUID so duplicate
        // display IDs (CloudKit sync conflicts) do not leak through. The execute() entry
        // point rejects ambiguity before we get here, so the resolved ID is authoritative.
        if filters.milestoneDisplayId != nil {
            guard let resolvedMilestoneId else { return false }
            return task.milestone?.id == resolvedMilestoneId
        }
        if let milestoneName = filters.milestone {
            guard let taskMilestone = task.milestone else { return false }
            return taskMilestone.name.localizedCaseInsensitiveCompare(milestoneName) == .orderedSame
        }
        return true
    }

    /// Resolves the optional `milestoneDisplayId` filter through `MilestoneService`
    /// so duplicate display IDs (possible via CloudKit sync conflicts) are rejected
    /// as ambiguous rather than silently matching tasks from every duplicate. [T-1146]
    @MainActor private static func resolveMilestoneDisplayIdFilter(
        _ filters: QueryFilters,
        milestoneService: MilestoneService
    ) -> MilestoneDisplayIdResolution {
        guard let milestoneDisplayId = filters.milestoneDisplayId else { return .unfiltered }
        do {
            let milestone = try milestoneService.findByDisplayID(milestoneDisplayId)
            return .resolved(milestone.id)
        } catch MilestoneService.Error.duplicateDisplayID {
            return .error(.internalError(
                hint: "Duplicate milestone identifier detected for displayId \(milestoneDisplayId)"
            ))
        } catch {
            return .notFound
        }
    }

    @MainActor private static func dateRange(from filter: DateRangeFilter) -> DateFilterHelpers.DateRange? {
        DateFilterHelpers.parseDateFilter(
            relative: filter.relative,
            from: filter.from,
            toDateString: filter.toDate
        )
    }

}
