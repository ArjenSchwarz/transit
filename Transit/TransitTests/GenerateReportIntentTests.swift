import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct GenerateReportIntentTests {

    private struct TestEnv {
        let context: ModelContext
        let taskService: TaskService
        let milestoneService: MilestoneService
    }

    private func makeEnv() throws -> TestEnv {
        let ctx = try makeReportTestContext()
        let store = InMemoryCounterStore()
        return TestEnv(
            context: ctx,
            taskService: TaskService(modelContext: ctx, displayIDAllocator: DisplayIDAllocator(store: store)),
            milestoneService: MilestoneService(
                modelContext: ctx, displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore())
            )
        )
    }

    @Test("Date range returns non-empty Markdown for matching tasks")
    func dateRangeReturnsMarkdown() throws {
        let env = try makeEnv()
        let now = reportTestNow
        let project = makeTestProject(name: "Alpha", context: env.context)
        makeTerminalTask(name: "Ship feature", project: project, completionDate: now, context: env.context)

        let markdown = GenerateReportIntent.execute(
            dateRange: .thisYear, taskService: env.taskService, milestoneService: env.milestoneService
        )

        #expect(markdown.contains("# Report: This Year"))
        #expect(markdown.contains("Ship feature"))
        #expect(!markdown.contains("No tasks completed or abandoned in this period."))
    }

    @Test("Empty date range returns empty-state Markdown")
    func emptyDateRangeReturnsEmptyState() throws {
        let env = try makeEnv()
        let now = reportTestNow
        let project = makeTestProject(name: "Alpha", context: env.context)
        // Task is at reportTestNow (Feb 18, 2026), so lastYear (2025) should be empty
        makeTerminalTask(name: "Recent task", project: project, completionDate: now, context: env.context)

        let markdown = GenerateReportIntent.execute(
            dateRange: .lastYear, taskService: env.taskService, milestoneService: env.milestoneService
        )

        #expect(markdown.contains("# Report: Last Year"))
        #expect(markdown.contains("No tasks completed or abandoned in this period."))
    }

    @Test("All date range cases produce valid output")
    func allCasesProduceValidOutput() throws {
        let env = try makeEnv()
        let now = reportTestNow
        let calendar = Calendar.current
        let project = makeTestProject(name: "Project", context: env.context)

        // Seed tasks spanning different time ranges to cover all cases
        // today
        makeTerminalTask(name: "Today", project: project, completionDate: now, context: env.context)
        // yesterday
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
            .addingTimeInterval(12 * 3600)
        makeTerminalTask(name: "Yesterday", project: project, completionDate: yesterday, context: env.context)
        // last week
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        makeTerminalTask(name: "LastWeek", project: project, completionDate: lastWeek, context: env.context)
        // last month
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
        makeTerminalTask(name: "LastMonth", project: project, completionDate: lastMonth, context: env.context)
        // last year
        let lastYear = calendar.date(byAdding: .year, value: -1, to: now)!
        makeTerminalTask(name: "LastYear", project: project, completionDate: lastYear, context: env.context)

        for dateRange in ReportDateRange.allCases {
            let markdown = GenerateReportIntent.execute(
                dateRange: dateRange, taskService: env.taskService, milestoneService: env.milestoneService
            )
            #expect(!markdown.isEmpty, "Output for \(dateRange.rawValue) should not be empty")
            #expect(markdown.contains("# Report:"), "Output for \(dateRange.rawValue) should contain report header")
        }
    }
}
