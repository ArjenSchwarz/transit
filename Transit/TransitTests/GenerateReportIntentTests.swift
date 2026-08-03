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

    private struct FetchFailure: Swift.Error {}

    private struct FailingTerminalTaskFetcher: TerminalTaskFetching {
        func fetchTerminalTasks() throws -> [TransitTask] { throw FetchFailure() }
    }

    private struct EmptyTerminalTaskFetcher: TerminalTaskFetching {
        func fetchTerminalTasks() throws -> [TransitTask] { [] }
    }

    private struct FailingTerminalMilestoneFetcher: TerminalMilestoneFetching {
        func fetchTerminalMilestones() throws -> [Milestone] { throw FetchFailure() }
    }

    private struct EmptyTerminalMilestoneFetcher: TerminalMilestoneFetching {
        func fetchTerminalMilestones() throws -> [Milestone] { [] }
    }

    private func makeEnv() throws -> TestEnv {
        let testContainer = try makeReportTestContainer()
        let ctx = testContainer.context
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
            dateRange: .thisYear,
            taskService: env.taskService,
            milestoneService: env.milestoneService,
            now: reportTestNow
        )

        #expect(markdown.contains("# Report: This Year"))
        #expect(markdown.contains("Ship feature"))
        #expect(!markdown.contains("No tasks completed or abandoned in this period."))
    }

    @Test("Task fetch failure returns the exact INTERNAL_ERROR payload")
    func taskFetchFailureReturnsInternalError() throws {
        let env = try makeEnv()

        let result = GenerateReportIntent.execute(
            dateRange: .lastYear,
            taskService: env.taskService,
            milestoneService: env.milestoneService,
            taskFetcher: FailingTerminalTaskFetcher(),
            now: reportTestNow
        )

        #expect(result == IntentError.internalError(hint: "Failed to fetch terminal tasks").json)
    }

    @Test("Milestone fetch failure returns the exact INTERNAL_ERROR payload")
    func milestoneFetchFailureReturnsInternalError() throws {
        let env = try makeEnv()

        let result = GenerateReportIntent.execute(
            dateRange: .lastYear,
            taskService: env.taskService,
            milestoneService: env.milestoneService,
            taskFetcher: EmptyTerminalTaskFetcher(),
            milestoneFetcher: FailingTerminalMilestoneFetcher(),
            now: reportTestNow
        )

        #expect(result == IntentError.internalError(hint: "Failed to fetch terminal milestones").json)
    }

    @Test("Successful empty fetches preserve exact empty-state Markdown")
    func validEmptyReportPreservesMarkdownAndDateRange() throws {
        let env = try makeEnv()
        let expected = ReportMarkdownFormatter.format(
            ReportLogic.buildReport(tasks: [], milestones: [], dateRange: .lastYear, now: reportTestNow)
        )

        let result = GenerateReportIntent.execute(
            dateRange: .lastYear,
            taskService: env.taskService,
            milestoneService: env.milestoneService,
            taskFetcher: EmptyTerminalTaskFetcher(),
            milestoneFetcher: EmptyTerminalMilestoneFetcher(),
            now: reportTestNow
        )

        #expect(result == expected)
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
                dateRange: dateRange,
                taskService: env.taskService,
                milestoneService: env.milestoneService,
                now: reportTestNow
            )
            #expect(!markdown.isEmpty, "Output for \(dateRange.rawValue) should not be empty")
            #expect(markdown.contains("# Report:"), "Output for \(dateRange.rawValue) should contain report header")
        }
    }
}
