import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct ReportLogicDateRangeTests {

    @Test("Today filter includes only tasks completed today")
    func todayFilter() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let today = makeTerminalTask(name: "Today", project: project, completionDate: now, context: ctx)
        let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        makeTerminalTask(name: "Yesterday", project: project, completionDate: yesterdayDate, context: ctx)

        let report = ReportLogic.buildReport(tasks: [today], dateRange: .today, now: now)
        // Passing only today's task since we want to verify the filter; also test with both:
        let fullReport = ReportLogic.buildReport(
            tasks: ctx.registeredObjects.compactMap { $0 as? TransitTask },
            dateRange: .today, now: now
        )

        #expect(report.projectGroups.flatMap(\.tasks).map(\.name) == ["Today"])
        #expect(fullReport.projectGroups.flatMap(\.tasks).map(\.name) == ["Today"])
    }

    @Test("Yesterday filter includes only tasks completed yesterday")
    func yesterdayFilter() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let calendar = Calendar.current
        let project = makeTestProject(name: "Project", context: ctx)

        let startOfToday = calendar.startOfDay(for: now)
        let yesterdayNoon = calendar.date(
            byAdding: .day, value: -1, to: startOfToday
        )!.addingTimeInterval(12 * 3600)

        let yTask = makeTerminalTask(
            name: "Yesterday", project: project, completionDate: yesterdayNoon, context: ctx
        )
        let tTask = makeTerminalTask(name: "Today", project: project, completionDate: now, context: ctx)

        let report = ReportLogic.buildReport(tasks: [yTask, tTask], dateRange: .yesterday, now: now)
        #expect(report.projectGroups.flatMap(\.tasks).map(\.name) == ["Yesterday"])
    }

    @Test("This week filter includes tasks from current week")
    func thisWeekFilter() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let calendar = Calendar.current
        let project = makeTestProject(name: "Project", context: ctx)

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start

        let inWeek = makeTerminalTask(
            name: "InWeek", project: project,
            completionDate: weekStart.addingTimeInterval(3600), context: ctx
        )
        let beforeWeek = makeTerminalTask(
            name: "BeforeWeek", project: project,
            completionDate: weekStart.addingTimeInterval(-3600), context: ctx
        )

        let report = ReportLogic.buildReport(tasks: [inWeek, beforeWeek], dateRange: .thisWeek, now: now)
        #expect(report.projectGroups.flatMap(\.tasks).map(\.name) == ["InWeek"])
    }

    @Test("Last week filter includes tasks from previous week")
    func lastWeekFilter() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let calendar = Calendar.current
        let project = makeTestProject(name: "Project", context: ctx)

        let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: lastWeekDate)!.start

        let inLastWeek = makeTerminalTask(
            name: "LastWeek", project: project,
            completionDate: lastWeekStart.addingTimeInterval(3600), context: ctx
        )
        let inThisWeek = makeTerminalTask(
            name: "ThisWeek", project: project, completionDate: now, context: ctx
        )

        let report = ReportLogic.buildReport(tasks: [inLastWeek, inThisWeek], dateRange: .lastWeek, now: now)
        #expect(report.projectGroups.flatMap(\.tasks).map(\.name) == ["LastWeek"])
    }

    @Test("This month filter includes tasks from current month")
    func thisMonthFilter() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let calendar = Calendar.current
        let project = makeTestProject(name: "Project", context: ctx)

        let monthStart = calendar.dateInterval(of: .month, for: now)!.start

        let inMonth = makeTerminalTask(
            name: "InMonth", project: project,
            completionDate: monthStart.addingTimeInterval(3600), context: ctx
        )
        let beforeMonth = makeTerminalTask(
            name: "BeforeMonth", project: project,
            completionDate: monthStart.addingTimeInterval(-3600), context: ctx
        )

        let report = ReportLogic.buildReport(tasks: [inMonth, beforeMonth], dateRange: .thisMonth, now: now)
        #expect(report.projectGroups.flatMap(\.tasks).map(\.name) == ["InMonth"])
    }

    @Test("Last month filter includes tasks from previous month")
    func lastMonthFilter() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let calendar = Calendar.current
        let project = makeTestProject(name: "Project", context: ctx)

        let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now)!
        let lastMonthStart = calendar.dateInterval(of: .month, for: lastMonthDate)!.start

        let inLastMonth = makeTerminalTask(
            name: "LastMonth", project: project,
            completionDate: lastMonthStart.addingTimeInterval(3600), context: ctx
        )
        let inThisMonth = makeTerminalTask(
            name: "ThisMonth", project: project, completionDate: now, context: ctx
        )

        let report = ReportLogic.buildReport(
            tasks: [inLastMonth, inThisMonth], dateRange: .lastMonth, now: now
        )
        #expect(report.projectGroups.flatMap(\.tasks).map(\.name) == ["LastMonth"])
    }

    @Test("This year filter includes tasks from current year")
    func thisYearFilter() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let calendar = Calendar.current
        let project = makeTestProject(name: "Project", context: ctx)

        let yearStart = calendar.dateInterval(of: .year, for: now)!.start

        let inYear = makeTerminalTask(
            name: "InYear", project: project,
            completionDate: yearStart.addingTimeInterval(3600), context: ctx
        )
        let beforeYear = makeTerminalTask(
            name: "BeforeYear", project: project,
            completionDate: yearStart.addingTimeInterval(-3600), context: ctx
        )

        let report = ReportLogic.buildReport(tasks: [inYear, beforeYear], dateRange: .thisYear, now: now)
        #expect(report.projectGroups.flatMap(\.tasks).map(\.name) == ["InYear"])
    }

    @Test("Last year filter includes tasks from previous year")
    func lastYearFilter() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let calendar = Calendar.current
        let project = makeTestProject(name: "Project", context: ctx)

        let lastYearDate = calendar.date(byAdding: .year, value: -1, to: now)!
        let lastYearStart = calendar.dateInterval(of: .year, for: lastYearDate)!.start

        let inLastYear = makeTerminalTask(
            name: "LastYear", project: project,
            completionDate: lastYearStart.addingTimeInterval(3600), context: ctx
        )
        let inThisYear = makeTerminalTask(
            name: "ThisYear", project: project, completionDate: now, context: ctx
        )

        let report = ReportLogic.buildReport(
            tasks: [inLastYear, inThisYear], dateRange: .lastYear, now: now
        )
        #expect(report.projectGroups.flatMap(\.tasks).map(\.name) == ["LastYear"])
    }

    // MARK: - Boundary Timestamps

    @Test("Yesterday boundary: start included, start of today excluded")
    func yesterdayBoundary() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let calendar = Calendar.current
        let project = makeTestProject(name: "Project", context: ctx)

        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!

        let atStart = makeTerminalTask(
            name: "AtStart", project: project, completionDate: startOfYesterday, context: ctx
        )
        let justBeforeEnd = makeTerminalTask(
            name: "JustBeforeEnd", project: project,
            completionDate: startOfToday.addingTimeInterval(-1), context: ctx
        )
        let atEnd = makeTerminalTask(
            name: "AtEnd", project: project, completionDate: startOfToday, context: ctx
        )

        let report = ReportLogic.buildReport(
            tasks: [atStart, justBeforeEnd, atEnd], dateRange: .yesterday, now: now
        )

        let names = report.projectGroups.flatMap(\.tasks).map(\.name)
        #expect(names.contains("AtStart"))
        #expect(names.contains("JustBeforeEnd"))
        #expect(!names.contains("AtEnd"))
    }

    @Test("Last week boundary: start included, this week start excluded")
    func lastWeekBoundary() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let calendar = Calendar.current
        let project = makeTestProject(name: "Project", context: ctx)

        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: lastWeekDate)!.start

        let atStart = makeTerminalTask(
            name: "AtStart", project: project, completionDate: lastWeekStart, context: ctx
        )
        let atEnd = makeTerminalTask(
            name: "AtEnd", project: project, completionDate: thisWeekStart, context: ctx
        )

        let report = ReportLogic.buildReport(tasks: [atStart, atEnd], dateRange: .lastWeek, now: now)

        let names = report.projectGroups.flatMap(\.tasks).map(\.name)
        #expect(names.contains("AtStart"))
        #expect(!names.contains("AtEnd"))
    }

    @Test("Empty result when no tasks match the date range")
    func emptyResultForMismatchedRange() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let oldDate = Calendar.current.date(byAdding: .year, value: -1, to: now)!
        let old = makeTerminalTask(name: "Old", project: project, completionDate: oldDate, context: ctx)

        let report = ReportLogic.buildReport(tasks: [old], dateRange: .today, now: now)

        #expect(report.isEmpty)
        #expect(report.projectGroups.isEmpty)
        #expect(report.totalDone == 0)
        #expect(report.totalAbandoned == 0)
    }
}
