import AppIntents
import Foundation
import SwiftData

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
    var status: String?
    var type: String?
    var projectId: String?
    var completionDate: DateRangeFilter?
    var lastStatusChangeDate: DateRangeFilter?

    init(
        status: String? = nil,
        type: String? = nil,
        projectId: String? = nil,
        completionDate: DateRangeFilter? = nil,
        lastStatusChangeDate: DateRangeFilter? = nil
    ) {
        self.status = status
        self.type = type
        self.projectId = projectId
        self.completionDate = completionDate
        self.lastStatusChangeDate = lastStatusChangeDate
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
        JSON object with optional filters: "status" (idea | planning | spec | ready-for-implementation | \
        in-progress | ready-for-review | done | abandoned), "type" (bug | feature | chore | research | \
        documentation), "projectId" (UUID), "completionDate", "lastStatusChangeDate". \
        Date filters accept {"relative":"today|this-week|this-month"} or {"from":"YYYY-MM-DD","to":"YYYY-MM-DD"} \
        (from/to optional and inclusive; relative takes precedence if both are present). \
        All filters are optional. Example: {"status":"in-progress"} or \
        {"completionDate":{"relative":"today"}} or {"lastStatusChangeDate":{"from":"2026-02-01","to":"2026-02-11"}}.
        """
    )
    var input: String

    @Dependency
    private var projectService: ProjectService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = QueryTasksIntent.execute(
            input: input,
            projectService: projectService,
            modelContext: projectService.context
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        input: String,
        projectService: ProjectService,
        modelContext: ModelContext
    ) -> String {
        let filters = parseInput(input)
        guard let filters else {
            return IntentError.invalidInput(hint: "Expected valid JSON object").json
        }

        // Validate projectId filter if present
        if let error = validateProjectFilter(filters, projectService: projectService) {
            return error.json
        }

        // Validate date filters if present
        if let error = validateDateFilters(filters) {
            return error.json
        }

        let allTasks = (try? modelContext.fetch(FetchDescriptor<TransitTask>())) ?? []
        let filtered = applyFilters(filters, to: allTasks)
        return IntentHelpers.encodeJSONArray(filtered.map(taskToDict))
    }

    // MARK: - Private Helpers

    @MainActor private static func parseInput(_ input: String) -> QueryFilters? {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return QueryFilters()
        }
        guard let data = input.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(QueryFilters.self, from: data)
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
        to tasks: [TransitTask]
    ) -> [TransitTask] {
        let completionRange = filters.completionDate.flatMap(dateRange)
        let lastStatusChangeRange = filters.lastStatusChangeDate.flatMap(dateRange)
        let projectId = filters.projectId.flatMap(UUID.init)

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
            if let completionRange {
                guard let completionDate = task.completionDate,
                      DateFilterHelpers.dateInRange(completionDate, range: completionRange) else {
                    continue
                }
            }
            if let lastStatusChangeRange,
               !DateFilterHelpers.dateInRange(task.lastStatusChangeDate, range: lastStatusChangeRange) {
                continue
            }
            result.append(task)
        }
        return result
    }

    @MainActor private static func dateRange(from filter: DateRangeFilter) -> DateFilterHelpers.DateRange? {
        DateFilterHelpers.parseDateFilter(
            relative: filter.relative,
            from: filter.from,
            toDateString: filter.toDate
        )
    }

    @MainActor private static func taskToDict(_ task: TransitTask) -> [String: Any] {
        let isoFormatter = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "taskId": task.id.uuidString,
            "name": task.name,
            "status": task.statusRawValue,
            "type": task.typeRawValue,
            "lastStatusChangeDate": isoFormatter.string(from: task.lastStatusChangeDate)
        ]
        if let displayId = task.permanentDisplayId {
            dict["displayId"] = displayId
        }
        if let projectId = task.project?.id.uuidString {
            dict["projectId"] = projectId
        }
        if let projectName = task.project?.name {
            dict["projectName"] = projectName
        }
        if let completionDate = task.completionDate {
            dict["completionDate"] = isoFormatter.string(from: completionDate)
        } else {
            dict["completionDate"] = NSNull()
        }
        return dict
    }
}
