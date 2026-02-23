import AppIntents
import Foundation
import os
import SwiftData

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
    private var projectService: ProjectService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = GenerateReportIntent.execute(
            dateRange: dateRange,
            modelContext: projectService.context
        )
        return .result(value: result)
    }

    @MainActor
    static func execute(dateRange: ReportDateRange, modelContext: ModelContext) -> String {
        let taskPredicate = #Predicate<TransitTask> {
            $0.statusRawValue == "done" || $0.statusRawValue == "abandoned"
        }
        var taskDescriptor = FetchDescriptor<TransitTask>(predicate: taskPredicate)
        taskDescriptor.relationshipKeyPathsForPrefetching = [\.project]

        let milestonePredicate = #Predicate<Milestone> {
            $0.statusRawValue == "done" || $0.statusRawValue == "abandoned"
        }
        var milestoneDescriptor = FetchDescriptor<Milestone>(predicate: milestonePredicate)
        milestoneDescriptor.relationshipKeyPathsForPrefetching = [\.project]

        let tasks: [TransitTask]
        let milestones: [Milestone]
        do {
            tasks = try modelContext.fetch(taskDescriptor)
            milestones = try modelContext.fetch(milestoneDescriptor)
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
