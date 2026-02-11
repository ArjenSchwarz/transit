import Foundation
import Testing
@testable import Transit

@MainActor
struct DateFilterHelpersTests {
    @Test("parse relative filter", arguments: [
        ("today", DateFilterHelpers.DateRange.today),
        ("this-week", DateFilterHelpers.DateRange.thisWeek),
        ("this-month", DateFilterHelpers.DateRange.thisMonth)
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
}
