import Foundation
import Testing
@testable import Transit

@MainActor
struct DateFilterHelpersTests {

    // MARK: - parseDateFilter

    @Test func parseDateFilterReturnsNilForEmptyJSON() {
        let json: [String: Any] = [:]
        let result = DateFilterHelpers.parseDateFilter(json)
        #expect(result == nil)
    }

    @Test func parseDateFilterParsesTodayRelative() {
        let json: [String: Any] = ["relative": "today"]
        let result = DateFilterHelpers.parseDateFilter(json)

        guard case .today = result else {
            Issue.record("Expected .today, got \(String(describing: result))")
            return
        }
    }

    @Test func parseDateFilterParsesThisWeekRelative() {
        let json: [String: Any] = ["relative": "this-week"]
        let result = DateFilterHelpers.parseDateFilter(json)

        guard case .thisWeek = result else {
            Issue.record("Expected .thisWeek, got \(String(describing: result))")
            return
        }
    }

    @Test func parseDateFilterParsesThisMonthRelative() {
        let json: [String: Any] = ["relative": "this-month"]
        let result = DateFilterHelpers.parseDateFilter(json)

        guard case .thisMonth = result else {
            Issue.record("Expected .thisMonth, got \(String(describing: result))")
            return
        }
    }

    @Test func parseDateFilterReturnsNilForInvalidRelative() {
        let json: [String: Any] = ["relative": "invalid"]
        let result = DateFilterHelpers.parseDateFilter(json)
        #expect(result == nil)
    }

    @Test func parseDateFilterParsesAbsoluteRangeWithBothDates() {
        let json: [String: Any] = ["from": "2026-02-01", "to": "2026-02-11"]
        let result = DateFilterHelpers.parseDateFilter(json)

        guard case .absolute(let from, let to) = result else {
            Issue.record("Expected .absolute, got \(String(describing: result))")
            return
        }

        #expect(from != nil)
        #expect(to != nil)
    }

    @Test func parseDateFilterParsesAbsoluteRangeWithOnlyFrom() {
        let json: [String: Any] = ["from": "2026-02-01"]
        let result = DateFilterHelpers.parseDateFilter(json)

        guard case .absolute(let from, let to) = result else {
            Issue.record("Expected .absolute, got \(String(describing: result))")
            return
        }

        #expect(from != nil)
        #expect(to == nil)
    }

    @Test func parseDateFilterParsesAbsoluteRangeWithOnlyTo() {
        let json: [String: Any] = ["to": "2026-02-11"]
        let result = DateFilterHelpers.parseDateFilter(json)

        guard case .absolute(let from, let to) = result else {
            Issue.record("Expected .absolute, got \(String(describing: result))")
            return
        }

        #expect(from == nil)
        #expect(to != nil)
    }

    @Test func parseDateFilterHandlesInvalidDateFormat() {
        let json: [String: Any] = ["from": "invalid-date"]
        let result = DateFilterHelpers.parseDateFilter(json)

        guard case .absolute(let from, let to) = result else {
            Issue.record("Expected .absolute, got \(String(describing: result))")
            return
        }

        #expect(from == nil)
        #expect(to == nil)
    }

    @Test func parseDateFilterPrefersRelativeOverAbsolute() {
        let json: [String: Any] = ["relative": "today", "from": "2026-02-01", "to": "2026-02-11"]
        let result = DateFilterHelpers.parseDateFilter(json)

        guard case .today = result else {
            Issue.record("Expected .today (relative should take precedence), got \(String(describing: result))")
            return
        }
    }

    // MARK: - dateInRange - Today

    @Test func dateInRangeTodayReturnsTrueForNow() {
        let now = Date()
        let result = DateFilterHelpers.dateInRange(now, range: .today)
        #expect(result == true)
    }

    @Test func dateInRangeTodayReturnsTrueForStartOfDay() {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let result = DateFilterHelpers.dateInRange(startOfToday, range: .today)
        #expect(result == true)
    }

    @Test func dateInRangeTodayReturnsTrueForEndOfDay() {
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .second, value: -1, to: calendar.startOfDay(for: Date().addingTimeInterval(86400)))!
        let result = DateFilterHelpers.dateInRange(endOfToday, range: .today)
        #expect(result == true)
    }

    @Test func dateInRangeTodayReturnsFalseForYesterday() {
        let yesterday = Date().addingTimeInterval(-86400)
        let result = DateFilterHelpers.dateInRange(yesterday, range: .today)
        #expect(result == false)
    }

    @Test func dateInRangeTodayReturnsFalseForTomorrow() {
        let tomorrow = Date().addingTimeInterval(86400)
        let result = DateFilterHelpers.dateInRange(tomorrow, range: .today)
        #expect(result == false)
    }

    // MARK: - dateInRange - This Week

    @Test func dateInRangeThisWeekReturnsTrueForNow() {
        let now = Date()
        let result = DateFilterHelpers.dateInRange(now, range: .thisWeek)
        #expect(result == true)
    }

    @Test func dateInRangeThisWeekReturnsTrueForStartOfWeek() {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            Issue.record("Could not get week interval")
            return
        }
        let result = DateFilterHelpers.dateInRange(weekInterval.start, range: .thisWeek)
        #expect(result == true)
    }

    @Test func dateInRangeThisWeekReturnsFalseForLastWeek() {
        let lastWeek = Date().addingTimeInterval(-7 * 86400)
        let result = DateFilterHelpers.dateInRange(lastWeek, range: .thisWeek)
        #expect(result == false)
    }

    @Test func dateInRangeThisWeekReturnsFalseForNextWeek() {
        let nextWeek = Date().addingTimeInterval(7 * 86400)
        let result = DateFilterHelpers.dateInRange(nextWeek, range: .thisWeek)
        #expect(result == false)
    }

    // MARK: - dateInRange - This Month

    @Test func dateInRangeThisMonthReturnsTrueForNow() {
        let now = Date()
        let result = DateFilterHelpers.dateInRange(now, range: .thisMonth)
        #expect(result == true)
    }

    @Test func dateInRangeThisMonthReturnsTrueForStartOfMonth() {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: Date()) else {
            Issue.record("Could not get month interval")
            return
        }
        let result = DateFilterHelpers.dateInRange(monthInterval.start, range: .thisMonth)
        #expect(result == true)
    }

    @Test func dateInRangeThisMonthReturnsFalseForLastMonth() {
        let calendar = Calendar.current
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date())!
        let result = DateFilterHelpers.dateInRange(lastMonth, range: .thisMonth)
        #expect(result == false)
    }

    @Test func dateInRangeThisMonthReturnsFalseForNextMonth() {
        let calendar = Calendar.current
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date())!
        let result = DateFilterHelpers.dateInRange(nextMonth, range: .thisMonth)
        #expect(result == false)
    }

    // MARK: - dateInRange - Absolute Range

    @Test func dateInRangeAbsoluteReturnsTrueForDateInRange() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let to = calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))!
        let testDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))!

        let result = DateFilterHelpers.dateInRange(testDate, range: .absolute(from: from, to: to))
        #expect(result == true)
    }

    @Test func dateInRangeAbsoluteReturnsTrueForFromBoundary() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let to = calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))!

        let result = DateFilterHelpers.dateInRange(from, range: .absolute(from: from, to: to))
        #expect(result == true)
    }

    @Test func dateInRangeAbsoluteReturnsTrueForToBoundary() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let to = calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))!

        let result = DateFilterHelpers.dateInRange(to, range: .absolute(from: from, to: to))
        #expect(result == true)
    }

    @Test func dateInRangeAbsoluteReturnsFalseForDateBeforeRange() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let to = calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))!
        let testDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!

        let result = DateFilterHelpers.dateInRange(testDate, range: .absolute(from: from, to: to))
        #expect(result == false)
    }

    @Test func dateInRangeAbsoluteReturnsFalseForDateAfterRange() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let to = calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))!
        let testDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 12))!

        let result = DateFilterHelpers.dateInRange(testDate, range: .absolute(from: from, to: to))
        #expect(result == false)
    }

    @Test func dateInRangeAbsoluteWithOnlyFromReturnsTrueForDateAfterFrom() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let testDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))!

        let result = DateFilterHelpers.dateInRange(testDate, range: .absolute(from: from, to: nil))
        #expect(result == true)
    }

    @Test func dateInRangeAbsoluteWithOnlyFromReturnsFalseForDateBeforeFrom() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let testDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!

        let result = DateFilterHelpers.dateInRange(testDate, range: .absolute(from: from, to: nil))
        #expect(result == false)
    }

    @Test func dateInRangeAbsoluteWithOnlyToReturnsTrueForDateBeforeTo() {
        let calendar = Calendar.current
        let to = calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))!
        let testDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))!

        let result = DateFilterHelpers.dateInRange(testDate, range: .absolute(from: nil, to: to))
        #expect(result == true)
    }

    @Test func dateInRangeAbsoluteWithOnlyToReturnsFalseForDateAfterTo() {
        let calendar = Calendar.current
        let to = calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))!
        let testDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 12))!

        let result = DateFilterHelpers.dateInRange(testDate, range: .absolute(from: nil, to: to))
        #expect(result == false)
    }

    @Test func dateInRangeAbsoluteWithNeitherFromNorToReturnsTrue() {
        let testDate = Date()
        let result = DateFilterHelpers.dateInRange(testDate, range: .absolute(from: nil, to: nil))
        #expect(result == true)
    }

    // MARK: - Idempotence

    @Test func dateInRangeIsIdempotent() {
        let testDate = Date()
        let range = DateFilterHelpers.DateRange.today

        let result1 = DateFilterHelpers.dateInRange(testDate, range: range)
        let result2 = DateFilterHelpers.dateInRange(testDate, range: range)

        #expect(result1 == result2)
    }

    @Test func dateInRangeIsIdempotentForAbsoluteRange() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let to = calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))!
        let testDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 5))!
        let range = DateFilterHelpers.DateRange.absolute(from: from, to: to)

        let result1 = DateFilterHelpers.dateInRange(testDate, range: range)
        let result2 = DateFilterHelpers.dateInRange(testDate, range: range)

        #expect(result1 == result2)
    }

    // MARK: - Timezone Consistency

    @Test func dateInRangeUsesLocalTimezone() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let testDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 23, minute: 59))!

        let result = DateFilterHelpers.dateInRange(testDate, range: .absolute(from: from, to: nil))
        #expect(result == true)
    }

    // MARK: - Edge Cases

    @Test func dateInRangeHandlesDSTBoundaries() {
        // This test verifies behavior across DST transitions
        let calendar = Calendar.current
        // March 2026 DST transition (assuming US timezone)
        let beforeDST = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7))!
        let afterDST = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!

        let result = DateFilterHelpers.dateInRange(afterDST, range: .absolute(from: beforeDST, to: nil))
        #expect(result == true)
    }

    @Test func dateInRangeHandlesYearBoundaries() {
        let calendar = Calendar.current
        let lastDayOfYear = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31))!
        let firstDayOfYear = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        let result = DateFilterHelpers.dateInRange(firstDayOfYear, range: .absolute(from: lastDayOfYear, to: nil))
        #expect(result == true)
    }

    @Test func dateInRangeHandlesLeapYear() {
        let calendar = Calendar.current
        let leapDay = calendar.date(from: DateComponents(year: 2024, month: 2, day: 29))!
        let from = calendar.date(from: DateComponents(year: 2024, month: 2, day: 1))!
        let to = calendar.date(from: DateComponents(year: 2024, month: 3, day: 1))!

        let result = DateFilterHelpers.dateInRange(leapDay, range: .absolute(from: from, to: to))
        #expect(result == true)
    }
}
