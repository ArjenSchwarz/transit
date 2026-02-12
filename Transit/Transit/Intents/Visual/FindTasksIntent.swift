import AppIntents
import Foundation
import SwiftData

enum DateFilterOption: String, AppEnum {
    case today
    case thisWeek = "this-week"
    case thisMonth = "this-month"
    case customRange = "custom-range"

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Date Filter")
    }

    nonisolated static var caseDisplayRepresentations: [DateFilterOption: DisplayRepresentation] {
        [
            .today: "Today",
            .thisWeek: "This Week",
            .thisMonth: "This Month",
            .customRange: "Custom Range"
        ]
    }
}

struct FindTasksIntent: AppIntent {
    struct Filters {
        let type: TaskType?
        let project: ProjectEntity?
        let status: TaskStatus?
        let completionDateFilter: DateFilterOption?
        let completionFromDate: Date?
        let completionToDate: Date?
        let lastStatusChangeDateFilter: DateFilterOption?
        let lastStatusChangeFromDate: Date?
        let lastStatusChangeToDate: Date?
    }

    private static let maxResults = 200

    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Find Tasks"

    nonisolated(unsafe) static var description = IntentDescription(
        "Find tasks with optional filters for type, project, status, and dates.",
        categoryName: "Tasks",
        resultValueName: "Tasks"
    )

    nonisolated(unsafe) static var supportedModes: IntentModes = [.background]

    @Parameter(title: "Type")
    var type: TaskType?

    @Parameter(title: "Project")
    var project: ProjectEntity?

    @Parameter(title: "Status")
    var status: TaskStatus?

    @Parameter(title: "Completion Date")
    var completionDateFilter: DateFilterOption?

    @Parameter(title: "Completed From")
    var completionFromDate: Date?

    @Parameter(title: "Completed To")
    var completionToDate: Date?

    @Parameter(title: "Last Changed")
    var lastStatusChangeDateFilter: DateFilterOption?

    @Parameter(title: "Changed From")
    var lastStatusChangeFromDate: Date?

    @Parameter(title: "Changed To")
    var lastStatusChangeToDate: Date?

    static var parameterSummary: some ParameterSummary {
        When(\.$completionDateFilter, .equalTo, .customRange) {
            When(\.$lastStatusChangeDateFilter, .equalTo, .customRange) {
                Summary("Find tasks") {
                    \.$type
                    \.$project
                    \.$status
                    \.$completionDateFilter
                    \.$completionFromDate
                    \.$completionToDate
                    \.$lastStatusChangeDateFilter
                    \.$lastStatusChangeFromDate
                    \.$lastStatusChangeToDate
                }
            } otherwise: {
                Summary("Find tasks") {
                    \.$type
                    \.$project
                    \.$status
                    \.$completionDateFilter
                    \.$completionFromDate
                    \.$completionToDate
                    \.$lastStatusChangeDateFilter
                }
            }
        } otherwise: {
            When(\.$lastStatusChangeDateFilter, .equalTo, .customRange) {
                Summary("Find tasks") {
                    \.$type
                    \.$project
                    \.$status
                    \.$completionDateFilter
                    \.$lastStatusChangeDateFilter
                    \.$lastStatusChangeFromDate
                    \.$lastStatusChangeToDate
                }
            } otherwise: {
                Summary("Find tasks") {
                    \.$type
                    \.$project
                    \.$status
                    \.$completionDateFilter
                    \.$lastStatusChangeDateFilter
                }
            }
        }
    }

    @Dependency
    private var projectService: ProjectService

    @MainActor
    func perform() async throws -> some ReturnsValue<[TaskEntity]> {
        let entities = try Self.execute(
            filters: Filters(
                type: type,
                project: project,
                status: status,
                completionDateFilter: completionDateFilter,
                completionFromDate: completionFromDate,
                completionToDate: completionToDate,
                lastStatusChangeDateFilter: lastStatusChangeDateFilter,
                lastStatusChangeFromDate: lastStatusChangeFromDate,
                lastStatusChangeToDate: lastStatusChangeToDate
            ),
            modelContext: projectService.context
        )
        return .result(value: entities)
    }

    // MARK: - Logic (testable without @Dependency)

    @MainActor
    static func execute(filters: Filters, modelContext: ModelContext) throws -> [TaskEntity] {
        let completionRange = try buildDateRange(
            option: filters.completionDateFilter,
            from: filters.completionFromDate,
            toDate: filters.completionToDate,
            fieldName: "completionDate"
        )

        let lastStatusChangeRange = try buildDateRange(
            option: filters.lastStatusChangeDateFilter,
            from: filters.lastStatusChangeFromDate,
            toDate: filters.lastStatusChangeToDate,
            fieldName: "lastStatusChangeDate"
        )

        let descriptor = FetchDescriptor<TransitTask>(
            sortBy: [SortDescriptor(\TransitTask.lastStatusChangeDate, order: .reverse)]
        )
        let tasks = try modelContext.fetch(descriptor)
        if tasks.isEmpty {
            return []
        }

        var filtered: [TransitTask] = []
        filtered.reserveCapacity(min(tasks.count, maxResults))

        for task in tasks {
            if let type = filters.type, task.type != type {
                continue
            }
            if let status = filters.status, task.status != status {
                continue
            }
            if let project = filters.project, task.project?.id != project.projectId {
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

            filtered.append(task)
        }

        let entities = TaskEntityQuery.entities(from: filtered)
        return Array(entities.prefix(maxResults))
    }

    @MainActor
    private static func buildDateRange(
        option: DateFilterOption?,
        from: Date?,
        toDate: Date?,
        fieldName: String
    ) throws -> DateFilterHelpers.DateRange? {
        guard let option else {
            return nil
        }

        switch option {
        case .today:
            return .today
        case .thisWeek:
            return .thisWeek
        case .thisMonth:
            return .thisMonth
        case .customRange:
            let calendar = Calendar.current
            if let from, let toDate, calendar.startOfDay(for: from) > calendar.startOfDay(for: toDate) {
                throw VisualIntentError.invalidDate("\(fieldName) from date must be before to date")
            }
            return .absolute(from: from, toDate: toDate)
        }
    }
}
