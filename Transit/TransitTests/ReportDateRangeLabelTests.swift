import Foundation
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct ReportDateRangeLabelTests {

    // MARK: - Regression: end dates must not be one day early (T-460)

    @Test("Last week label includes correct last day of previous week")
    func lastWeekLabelEndDate() {
        let now = reportTestNow // Wed Feb 18, 2026
        let calendar = Calendar.current

        // Compute the expected last day of the previous week
        let prevWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        let prevWeekInterval = calendar.dateInterval(of: .weekOfYear, for: prevWeekDate)!
        let expectedLastDay = calendar.date(byAdding: .day, value: -1, to: prevWeekInterval.end)!

        let label = ReportDateRange.lastWeek.labelWithDates(now: now)

        // Use the same abbreviated format to match locale-specific output
        let expectedEndStr = expectedLastDay.formatted(.dateTime.month(.abbreviated).day())
        #expect(
            label.contains(expectedEndStr),
            "Label '\(label)' should contain '\(expectedEndStr)' as end date"
        )
    }

    @Test("Last month label shows last day of January (31st)")
    func lastMonthLabelEndDate() {
        let now = reportTestNow // Wed Feb 18, 2026
        let calendar = Calendar.current

        let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: now)!
        let monthInterval = calendar.dateInterval(of: .month, for: prevMonthDate)!
        let expectedLastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end)!

        let label = ReportDateRange.lastMonth.labelWithDates(now: now)
        let expectedEndStr = expectedLastDay.formatted(.dateTime.day())

        // January 2026 has 31 days — label must show day 31, not 30
        #expect(
            label.contains(expectedEndStr),
            "Label '\(label)' should contain day '\(expectedEndStr)'"
        )
    }

    @Test("Last year label shows December 31 as end date")
    func lastYearLabelEndDate() {
        let now = reportTestNow // Wed Feb 18, 2026
        let calendar = Calendar.current

        let prevYearDate = calendar.date(byAdding: .year, value: -1, to: now)!
        let yearInterval = calendar.dateInterval(of: .year, for: prevYearDate)!
        let expectedLastDay = calendar.date(byAdding: .day, value: -1, to: yearInterval.end)!

        let label = ReportDateRange.lastYear.labelWithDates(now: now)
        let expectedEndStr = expectedLastDay.formatted(.dateTime.month(.abbreviated).day())

        #expect(
            label.contains(expectedEndStr),
            "Label '\(label)' should contain '\(expectedEndStr)' as end date"
        )
    }
}
