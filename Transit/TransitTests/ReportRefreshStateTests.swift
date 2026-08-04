import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct ReportRefreshStateTests {

    @Test("Current report ranges refresh at the next local midnight across DST")
    func currentRangesRefreshAtLocalMidnight() {
        let calendar = testCalendar()
        let now = testDate(year: 2026, month: 3, day: 8, hour: 0, minute: 30, calendar: calendar)
        let expected = testDate(year: 2026, month: 3, day: 9, hour: 0, minute: 0, calendar: calendar)

        for range in [ReportDateRange.today, .yesterday, .thisWeek, .thisMonth, .thisYear] {
            #expect(
                ReportRefreshScheduler.nextRefreshDate(for: range, now: now, calendar: calendar) == expected,
                "\(range.rawValue) should refresh at the next local midnight"
            )
        }
    }

    @Test("Completed report ranges refresh at their next calendar boundary")
    func completedRangesRefreshAtPeriodBoundary() {
        let calendar = testCalendar()
        let weekNow = testDate(year: 2026, month: 2, day: 18, hour: 14, minute: 0, calendar: calendar)
        let monthNow = testDate(year: 2026, month: 2, day: 18, hour: 14, minute: 0, calendar: calendar)
        let yearNow = testDate(year: 2026, month: 12, day: 15, hour: 14, minute: 0, calendar: calendar)

        #expect(
            ReportRefreshScheduler.nextRefreshDate(for: .lastWeek, now: weekNow, calendar: calendar)
                == testDate(year: 2026, month: 2, day: 23, hour: 0, minute: 0, calendar: calendar)
        )
        #expect(
            ReportRefreshScheduler.nextRefreshDate(for: .lastMonth, now: monthNow, calendar: calendar)
                == testDate(year: 2026, month: 3, day: 1, hour: 0, minute: 0, calendar: calendar)
        )
        #expect(
            ReportRefreshScheduler.nextRefreshDate(for: .lastYear, now: yearNow, calendar: calendar)
                == testDate(year: 2027, month: 1, day: 1, hour: 0, minute: 0, calendar: calendar)
        )
    }

    @Test("Refresh state rolls report contents and label with one captured clock value")
    func refreshStateRollsReportAndLabelTogether() throws {
        let context = try TestModelContainer.newContext()
        let calendar = testCalendar()
        let project = makeTestProject(name: "Project", context: context)
        let februaryTask = makeTerminalTask(
            name: "February", project: project,
            completionDate: testDate(year: 2026, month: 2, day: 28, hour: 23, minute: 30, calendar: calendar),
            context: context
        )
        let marchTask = makeTerminalTask(
            name: "March", project: project,
            completionDate: testDate(year: 2026, month: 3, day: 1, hour: 0, minute: 30, calendar: calendar),
            context: context
        )
        var now = testDate(year: 2026, month: 2, day: 28, hour: 23, minute: 59, calendar: calendar)
        var state = ReportRefreshState(clock: { now }, calendar: { calendar })

        let februaryReport = ReportLogic.buildReport(
            tasks: [februaryTask, marchTask],
            dateRange: .thisMonth,
            now: state.now,
            calendar: state.calendar
        )
        #expect(februaryReport.projectGroups.flatMap(\.tasks).map(\.name) == ["February"])
        #expect(
            februaryReport.dateRangeLabel
                == ReportDateRange.thisMonth.labelWithDates(now: state.now, calendar: state.calendar)
        )

        now = testDate(year: 2026, month: 3, day: 1, hour: 0, minute: 1, calendar: calendar)
        state.refresh()

        let marchReport = ReportLogic.buildReport(
            tasks: [februaryTask, marchTask],
            dateRange: .thisMonth,
            now: state.now,
            calendar: state.calendar
        )
        #expect(marchReport.projectGroups.flatMap(\.tasks).map(\.name) == ["March"])
        #expect(
            marchReport.dateRangeLabel
                == ReportDateRange.thisMonth.labelWithDates(now: state.now, calendar: state.calendar)
        )
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func testDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
