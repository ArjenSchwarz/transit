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
    private var taskService: TaskService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = GenerateReportIntent.execute(
            dateRange: dateRange,
            modelContext: taskService.modelContext
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
        let tasks = (try? modelContext.fetch(descriptor)) ?? []

        let report = ReportLogic.buildReport(tasks: tasks, dateRange: dateRange)
        return ReportMarkdownFormatter.format(report)
    }
}
