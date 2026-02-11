import AppIntents
import Foundation
import SwiftData

/// Searches for tasks with optional visual filters in Shortcuts.
/// Exposed as "Transit: Find Tasks" with native dropdowns for type, project, status,
/// and date filters. Runs in background mode for automation workflows.
struct FindTasksIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Find Tasks"

    nonisolated(unsafe) static var description = IntentDescription(
        "Search for tasks with optional filters for type, project, status, and dates",
        categoryName: "Tasks",
        resultValueName: "Tasks"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = false

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

    // Conditional parameters for completion date custom-range
    @Parameter(title: "Completed From")
    var completionFromDate: Date?

    @Parameter(title: "Completed To")
    var completionToDate: Date?

    // Conditional parameters for last changed custom-range
    @Parameter(title: "Changed From")
    var lastChangedFromDate: Date?

    @Parameter(title: "Changed To")
    var lastChangedToDate: Date?

    static var parameterSummary: some ParameterSummary {
        When(\.$completionDateFilter, .equalTo, DateFilterOption.customRange) {
            When(\.$lastChangedFilter, .equalTo, DateFilterOption.customRange) {
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

    @MainActor
    func perform() async throws -> some ReturnsValue<[TaskEntity]> {
        let result = try FindTasksIntent.execute(
            input: Input(
                type: type,
                project: project,
                status: status,
                completionDateFilter: completionDateFilter,
                lastChangedFilter: lastChangedFilter,
                completionFromDate: completionFromDate,
                completionToDate: completionToDate,
                lastChangedFromDate: lastChangedFromDate,
                lastChangedToDate: lastChangedToDate
            ),
            modelContext: projectService.context
        )
        return .result(value: result)
    }

    // MARK: - Testable Input

    struct Input {
        let type: TaskType?
        let project: ProjectEntity?
        let status: TaskStatus?
        let completionDateFilter: DateFilterOption?
        let lastChangedFilter: DateFilterOption?
        let completionFromDate: Date?
        let completionToDate: Date?
        let lastChangedFromDate: Date?
        let lastChangedToDate: Date?
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(
        input: Input,
        modelContext: ModelContext
    ) throws -> [TaskEntity] {
        let allTasks = (try? modelContext.fetch(FetchDescriptor<TransitTask>())) ?? []

        var filtered = allTasks

        // Type filter
        if let type = input.type {
            filtered = filtered.filter { $0.typeRawValue == type.rawValue }
        }

        // Project filter
        if let project = input.project {
            filtered = filtered.filter { $0.project?.id == project.projectId }
        }

        // Status filter
        if let status = input.status {
            filtered = filtered.filter { $0.statusRawValue == status.rawValue }
        }

        // Completion date filter
        if let completionRange = buildDateRange(
            option: input.completionDateFilter,
            from: input.completionFromDate,
            endDate: input.completionToDate
        ) {
            filtered = filtered.filter { task in
                guard let date = task.completionDate else { return false }
                return DateFilterHelpers.dateInRange(date, range: completionRange)
            }
        }

        // Last status change date filter
        if let statusChangeRange = buildDateRange(
            option: input.lastChangedFilter,
            from: input.lastChangedFromDate,
            endDate: input.lastChangedToDate
        ) {
            filtered = filtered.filter { task in
                DateFilterHelpers.dateInRange(task.lastStatusChangeDate, range: statusChangeRange)
            }
        }

        // Sort by lastStatusChangeDate descending
        let sorted = filtered.sorted { $0.lastStatusChangeDate > $1.lastStatusChangeDate }

        // Limit to 200 tasks
        let limited = Array(sorted.prefix(200))

        // Convert to TaskEntity, skipping tasks without projects (CloudKit sync edge case)
        return limited.compactMap { try? TaskEntity.from($0) }
    }

    // MARK: - Private Helpers

    private static func buildDateRange(
        option: DateFilterOption?,
        from: Date?,
        endDate: Date?
    ) -> DateFilterHelpers.DateRange? {
        guard let option else { return nil }

        switch option {
        case .today: return .today
        case .thisWeek: return .thisWeek
        case .thisMonth: return .thisMonth
        case .customRange: return .absolute(from: from, endDate: endDate)
        }
    }
}
