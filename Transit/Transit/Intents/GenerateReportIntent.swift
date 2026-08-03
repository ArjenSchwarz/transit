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
        milestoneService: MilestoneService,
        taskFetcher: (any TerminalTaskFetching)? = nil,
        milestoneFetcher: (any TerminalMilestoneFetching)? = nil,
        now: Date = .now
    ) -> String {
        let taskFetcher = taskFetcher ?? taskService
        let milestoneFetcher = milestoneFetcher ?? milestoneService
        let tasks: [TransitTask]
        do {
            tasks = try taskFetcher.fetchTerminalTasks()
        } catch {
            Logger(subsystem: "com.transit", category: "report")
                .error("Failed to fetch terminal tasks: \(error.localizedDescription)")
            return IntentError.internalError(hint: "Failed to fetch terminal tasks").json
        }

        let milestones: [Milestone]
        do {
            milestones = try milestoneFetcher.fetchTerminalMilestones()
        } catch {
            Logger(subsystem: "com.transit", category: "report")
                .error("Failed to fetch terminal milestones: \(error.localizedDescription)")
            return IntentError.internalError(hint: "Failed to fetch terminal milestones").json
        }

        let report = ReportLogic.buildReport(
            tasks: tasks,
            milestones: milestones,
            dateRange: dateRange,
            now: now
        )
        return ReportMarkdownFormatter.format(report)
    }
}
