import AppIntents
import Foundation
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
        let predicate = #Predicate<TransitTask> {
            $0.statusRawValue == "done" || $0.statusRawValue == "abandoned"
        }
        var descriptor = FetchDescriptor<TransitTask>(predicate: predicate)
        descriptor.relationshipKeyPathsForPrefetching = [\.project]

        let tasks: [TransitTask]
        do {
            tasks = try modelContext.fetch(descriptor)
        } catch {
            let emptyData = ReportData(
                dateRangeLabel: dateRange.labelWithDates(),
                projectGroups: [],
                totalDone: 0,
                totalAbandoned: 0
            )
            return ReportMarkdownFormatter.format(emptyData)
        }

        let report = ReportLogic.buildReport(tasks: tasks, dateRange: dateRange)
        return ReportMarkdownFormatter.format(report)
    }
}
