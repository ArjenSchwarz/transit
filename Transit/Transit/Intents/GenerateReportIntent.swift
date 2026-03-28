import AppIntents
import Foundation
import os

struct GenerateReportIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Generate Report"

    nonisolated(unsafe) static var description = IntentDescription(
        "Generate a Markdown report of completed and abandoned tasks for a date range.",
        categoryName: "Reports"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Parameter(title: "Date Range")
    var dateRange: ReportDateRange

    @Dependency
    private var taskService: TaskService

    @Dependency
    private var milestoneService: MilestoneService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = GenerateReportIntent.execute(
            dateRange: dateRange,
            taskService: taskService,
            milestoneService: milestoneService
        )
        return .result(value: result)
    }

    @MainActor
    static func execute(
        dateRange: ReportDateRange,
        taskService: TaskService,
        milestoneService: MilestoneService
    ) -> String {
        let tasks: [TransitTask]
        let milestones: [Milestone]
        do {
            tasks = try taskService.fetchTerminalTasks()
            milestones = try milestoneService.fetchTerminalMilestones()
        } catch {
            Logger(subsystem: "com.transit", category: "report")
                .error("Failed to fetch data for report: \(error.localizedDescription)")
            let emptyData = ReportData(
                dateRangeLabel: dateRange.labelWithDates(),
                projectGroups: [],
                totalDone: 0,
                totalAbandoned: 0
            )
            return ReportMarkdownFormatter.format(emptyData)
        }

        let report = ReportLogic.buildReport(tasks: tasks, milestones: milestones, dateRange: dateRange)
        return ReportMarkdownFormatter.format(report)
    }
}
