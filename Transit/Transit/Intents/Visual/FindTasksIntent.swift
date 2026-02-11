import AppIntents
import Foundation
import SwiftData

/// Visual Shortcuts intent for searching tasks with filters.
/// Exposed as "Transit: Find Tasks" in Shortcuts. [req 3.1-3.16]
struct FindTasksIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Find Tasks"

    nonisolated(unsafe) static var description = IntentDescription(
        "Search for tasks with optional filters for type, project, status, and dates",
        categoryName: "Tasks",
        resultValueName: "Tasks"
    )

    // Background mode only - doesn't open the app [req 3.15]
    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    // MARK: - Parameters

    @Parameter(title: "Type")
    var type: TaskType?

    @Parameter(title: "Project")
    var project: ProjectEntity?

    @Parameter(title: "Status")
    var status: TaskStatus?

    @Parameter(title: "Completion Date")
    var completionDateFilter: DateFilterOption?

    @Parameter(title: "Last Changed")
    var lastChangedFilter: DateFilterOption?

    // Conditional parameters for completion date custom-range [req 3.7]
    @Parameter(title: "Completed From")
    var completionFromDate: Date?

    @Parameter(title: "Completed To")
    var completionToDate: Date?

    // Conditional parameters for last changed custom-range [req 3.7]
    @Parameter(title: "Changed From")
    var lastChangedFromDate: Date?

    @Parameter(title: "Changed To")
    var lastChangedToDate: Date?

    // MARK: - Parameter Summary [req 3.7, 3.8]

    static var parameterSummary: some ParameterSummary {
        When(\.$completionDateFilter, .equalTo, DateFilterOption.customRange) {
            When(\.$lastChangedFilter, .equalTo, DateFilterOption.customRange) {
                // Both filters use custom-range: show all 4 date pickers
                Summary("Find tasks") {
                    \.$type
                    \.$project
                    \.$status
                    \.$completionDateFilter
                    \.$completionFromDate
                    \.$completionToDate
                    \.$lastChangedFilter
                    \.$lastChangedFromDate
                    \.$lastChangedToDate
                }
            } otherwise: {
                // Only completion uses custom-range
                Summary("Find tasks") {
                    \.$type
                    \.$project
                    \.$status
                    \.$completionDateFilter
                    \.$completionFromDate
                    \.$completionToDate
                    \.$lastChangedFilter
                }
            }
        } otherwise: {
            When(\.$lastChangedFilter, .equalTo, DateFilterOption.customRange) {
                // Only lastChanged uses custom-range
                Summary("Find tasks") {
                    \.$type
                    \.$project
                    \.$status
                    \.$completionDateFilter
                    \.$lastChangedFilter
                    \.$lastChangedFromDate
                    \.$lastChangedToDate
                }
            } otherwise: {
                // Neither uses custom-range
                Summary("Find tasks") {
                    \.$type
                    \.$project
                    \.$status
                    \.$completionDateFilter
                    \.$lastChangedFilter
                }
            }
        }
    }

    @Dependency
    private var projectService: ProjectService

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some ReturnsValue<[TaskEntity]> {
        let result = try await FindTasksIntent.execute(
            type: type,
            project: project,
            status: status,
            completionDateFilter: completionDateFilter,
            completionFromDate: completionFromDate,
            completionToDate: completionToDate,
            lastChangedFilter: lastChangedFilter,
            lastChangedFromDate: lastChangedFromDate,
            lastChangedToDate: lastChangedToDate,
            projectService: projectService
        )

        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        type: TaskType?,
        project: ProjectEntity?,
        status: TaskStatus?,
        completionDateFilter: DateFilterOption?,
        completionFromDate: Date?,
        completionToDate: Date?,
        lastChangedFilter: DateFilterOption?,
        lastChangedFromDate: Date?,
        lastChangedToDate: Date?,
        projectService: ProjectService
    ) async throws -> [TaskEntity] {
        // Fetch all tasks [req 3.16]
        let descriptor = FetchDescriptor<TransitTask>()
        let allTasks = try projectService.context.fetch(descriptor)

        // Apply filters using AND logic [req 3.14]
        var filtered = allTasks

        // Filter by type [req 3.2]
        if let type {
            filtered = filtered.filter { $0.type == type }
        }

        // Filter by project [req 3.3]
        if let project {
            filtered = filtered.filter { $0.project?.id == project.projectId }
        }

        // Filter by status [req 3.4]
        if let status {
            filtered = filtered.filter { $0.status == status }
        }

        // Filter by completion date [req 3.5, 3.6]
        if let completionRange = buildDateRange(
            option: completionDateFilter,
            from: completionFromDate,
            to: completionToDate
        ) {
            filtered = filtered.filter { task in
                guard let completionDate = task.completionDate else { return false }
                return DateFilterHelpers.dateInRange(completionDate, range: completionRange)
            }
        }

        // Filter by last status change date [req 3.6]
        if let lastChangedRange = buildDateRange(
            option: lastChangedFilter,
            from: lastChangedFromDate,
            to: lastChangedToDate
        ) {
            filtered = filtered.filter { task in
                DateFilterHelpers.dateInRange(task.lastStatusChangeDate, range: lastChangedRange)
            }
        }

        // Sort by lastStatusChangeDate descending [req 3.13]
        let sorted = filtered.sorted { $0.lastStatusChangeDate > $1.lastStatusChangeDate }

        // Limit to 200 tasks [req 3.12]
        let limited = Array(sorted.prefix(200))

        // Convert to TaskEntity array [req 3.8, 3.9]
        // Use compactMap to gracefully skip tasks without projects (CloudKit sync edge case)
        return limited.compactMap { try? TaskEntity.from($0) }
    }

    // MARK: - Helpers

    /// Convert DateFilterOption + Date parameters to DateRange
    private static func buildDateRange(
        option: DateFilterOption?,
        from: Date?,
        to: Date?
    ) -> DateFilterHelpers.DateRange? {
        guard let option else { return nil }

        switch option {
        case .today:
            return .today
        case .thisWeek:
            return .thisWeek
        case .thisMonth:
            return .thisMonth
        case .customRange:
            return .absolute(from: from, to: to)
        }
    }
}
