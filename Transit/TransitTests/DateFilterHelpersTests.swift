import Foundation
import Testing
@testable import Transit

@MainActor
struct DateFilterHelpersTests {
    @Test("parse relative filter", arguments: [
        ("today", DateFilterHelpers.DateRange.today),
        ("yesterday", DateFilterHelpers.DateRange.yesterday),
        ("this-week", DateFilterHelpers.DateRange.thisWeek),
        ("last-week", DateFilterHelpers.DateRange.lastWeek),
        ("this-month", DateFilterHelpers.DateRange.thisMonth),
        ("last-month", DateFilterHelpers.DateRange.lastMonth),
        ("this-year", DateFilterHelpers.DateRange.thisYear),
        ("last-year", DateFilterHelpers.DateRange.lastYear)
    ])
    func parseRelativeFilter(relative: String, expected: DateFilterHelpers.DateRange) {
        let parsed = DateFilterHelpers.parseDateFilter(["relative": relative])
        #expect(parsed == expected)
    }

    @Test func parseAbsoluteFilterFromAndTo() {
        let parsed = DateFilterHelpers.parseDateFilter([
            "from": "2026-02-01",
            "to": "2026-02-11"
        ])

        switch parsed {
        case .absolute(let from, let toDate):
            #expect(from != nil)
            #expect(toDate != nil)
        default:
            Issue.record("Expected absolute range")
        }
    }

    @Test func parseAbsoluteFilterRejectsInvalidDates() {
        let parsed = DateFilterHelpers.parseDateFilter([
            "from": "2026-99-99"
        ])
        #expect(parsed == nil)
    }

    @Test func absoluteRangeComparisonIsInclusive() {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: Date.now)
        let toDate = from.addingTimeInterval(2 * 24 * 60 * 60)
        let range = DateFilterHelpers.DateRange.absolute(from: from, toDate: toDate)

        #expect(DateFilterHelpers.dateInRange(from, range: range))
        #expect(DateFilterHelpers.dateInRange(toDate, range: range))
    }

    @Test func todayRangeIncludesCurrentDayAndExcludesPreviousDay() {
        let calendar = Calendar.current
        let now = Date.now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        #expect(DateFilterHelpers.dateInRange(now, range: .today, now: now))
        #expect(!DateFilterHelpers.dateInRange(yesterday, range: .today, now: now))
    }

    @Test func thisWeekStartsAtLocaleWeekBoundary() {
        let calendar = Calendar.current
        let now = Date.now
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let dayBeforeWeek = calendar.date(byAdding: .day, value: -1, to: startOfWeek)!

        #expect(DateFilterHelpers.dateInRange(startOfWeek, range: .thisWeek, now: now))
        #expect(!DateFilterHelpers.dateInRange(dayBeforeWeek, range: .thisWeek, now: now))
    }

    @Test func thisMonthStartsAtMonthBoundary() {
        let calendar = Calendar.current
        let now = Date.now
        let monthStart = calendar.dateInterval(of: .month, for: now)!.start
        let dayBeforeMonth = calendar.date(byAdding: .day, value: -1, to: monthStart)!

        #expect(DateFilterHelpers.dateInRange(monthStart, range: .thisMonth, now: now))
        #expect(!DateFilterHelpers.dateInRange(dayBeforeMonth, range: .thisMonth, now: now))
    }

    // MARK: - Yesterday

    @Test func yesterdayIncludesStartOfYesterday() {
        let calendar = Calendar.current
        let now = Date.now
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!

        #expect(DateFilterHelpers.dateInRange(startOfYesterday, range: .yesterday, now: now))
    }

    @Test func yesterdayExcludesMidnightToday() {
        let calendar = Calendar.current
        let now = Date.now
        let startOfToday = calendar.startOfDay(for: now)

        #expect(!DateFilterHelpers.dateInRange(startOfToday, range: .yesterday, now: now))
    }

    @Test func yesterdayExcludesTwoDaysAgo() {
        let calendar = Calendar.current
        let now = Date.now
        let startOfToday = calendar.startOfDay(for: now)
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: startOfToday)!

        #expect(!DateFilterHelpers.dateInRange(twoDaysAgo, range: .yesterday, now: now))
    }

    // MARK: - Last Week

    @Test func lastWeekIncludesStartOfLastWeek() {
        let calendar = Calendar.current
        let now = Date.now
        let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastWeekDate)!

        #expect(DateFilterHelpers.dateInRange(lastWeek.start, range: .lastWeek, now: now))
    }

    @Test func lastWeekExcludesEndBoundary() {
        let calendar = Calendar.current
        let now = Date.now
        let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastWeekDate)!

        // End of dateInterval is exclusive (start of next period)
        #expect(!DateFilterHelpers.dateInRange(lastWeek.end, range: .lastWeek, now: now))
    }

    @Test func lastWeekExcludesThisWeek() {
        let calendar = Calendar.current
        let now = Date.now
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)!

        #expect(!DateFilterHelpers.dateInRange(thisWeek.start, range: .lastWeek, now: now))
    }

    // MARK: - Last Month

    @Test func lastMonthIncludesStartOfLastMonth() {
        let calendar = Calendar.current
        let now = Date.now
        let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now)!
        let lastMonth = calendar.dateInterval(of: .month, for: lastMonthDate)!

        #expect(DateFilterHelpers.dateInRange(lastMonth.start, range: .lastMonth, now: now))
    }

    @Test func lastMonthExcludesEndBoundary() {
        let calendar = Calendar.current
        let now = Date.now
        let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now)!
        let lastMonth = calendar.dateInterval(of: .month, for: lastMonthDate)!

        #expect(!DateFilterHelpers.dateInRange(lastMonth.end, range: .lastMonth, now: now))
    }

    @Test func lastMonthExcludesThisMonth() {
        let calendar = Calendar.current
        let now = Date.now
        let thisMonth = calendar.dateInterval(of: .month, for: now)!

        #expect(!DateFilterHelpers.dateInRange(thisMonth.start, range: .lastMonth, now: now))
    }

    // MARK: - This Year

    @Test func thisYearIncludesJanFirst() {
        let calendar = Calendar.current
        let now = Date.now
        let year = calendar.dateInterval(of: .year, for: now)!

        #expect(DateFilterHelpers.dateInRange(year.start, range: .thisYear, now: now))
    }

    @Test func thisYearIncludesNow() {
        let now = Date.now
        #expect(DateFilterHelpers.dateInRange(now, range: .thisYear, now: now))
    }

    @Test func thisYearExcludesLastYear() {
        let calendar = Calendar.current
        let now = Date.now
        let year = calendar.dateInterval(of: .year, for: now)!
        let lastYearDate = calendar.date(byAdding: .second, value: -1, to: year.start)!

        #expect(!DateFilterHelpers.dateInRange(lastYearDate, range: .thisYear, now: now))
    }

    // MARK: - Last Year

    @Test func lastYearIncludesStartOfLastYear() {
        let calendar = Calendar.current
        let now = Date.now
        let lastYearDate = calendar.date(byAdding: .year, value: -1, to: now)!
        let lastYear = calendar.dateInterval(of: .year, for: lastYearDate)!

        #expect(DateFilterHelpers.dateInRange(lastYear.start, range: .lastYear, now: now))
    }

    @Test func lastYearExcludesEndBoundary() {
        let calendar = Calendar.current
        let now = Date.now
        let lastYearDate = calendar.date(byAdding: .year, value: -1, to: now)!
        let lastYear = calendar.dateInterval(of: .year, for: lastYearDate)!

        #expect(!DateFilterHelpers.dateInRange(lastYear.end, range: .lastYear, now: now))
    }

    @Test func lastYearExcludesThisYear() {
        let calendar = Calendar.current
        let now = Date.now
        let thisYear = calendar.dateInterval(of: .year, for: now)!

        #expect(!DateFilterHelpers.dateInRange(thisYear.start, range: .lastYear, now: now))
    }
}
