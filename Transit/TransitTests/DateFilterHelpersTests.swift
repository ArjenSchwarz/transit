import Foundation
import Testing
@testable import Transit

@MainActor
struct DateFilterHelpersTests {

    // MARK: - parseDateFilter: Relative Dates

    @Test func parseRelativeToday() throws {
        let json: [String: Any] = ["relative": "today"]
        let range = try DateFilterHelpers.parseDateFilter(json)
        guard case .today = range else {
            Issue.record("Expected .today, got \(String(describing: range))")
            return
        }
    }

    @Test func parseRelativeThisWeek() throws {
        let json: [String: Any] = ["relative": "this-week"]
        let range = try DateFilterHelpers.parseDateFilter(json)
        guard case .thisWeek = range else {
            Issue.record("Expected .thisWeek, got \(String(describing: range))")
            return
        }
    }

    @Test func parseRelativeThisMonth() throws {
        let json: [String: Any] = ["relative": "this-month"]
        let range = try DateFilterHelpers.parseDateFilter(json)
        guard case .thisMonth = range else {
            Issue.record("Expected .thisMonth, got \(String(describing: range))")
            return
        }
    }

    @Test func parseRelativeUnknownThrows() {
        let json: [String: Any] = ["relative": "last-year"]
        #expect(throws: VisualIntentError.self) {
            try DateFilterHelpers.parseDateFilter(json)
        }
    }

    // MARK: - parseDateFilter: Relative Takes Precedence (Decision 20)

    @Test func relativeTakesPrecedenceOverAbsolute() throws {
        let json: [String: Any] = [
            "relative": "today",
            "from": "2026-01-01",
            "to": "2026-12-31"
        ]
        let range = try DateFilterHelpers.parseDateFilter(json)
        guard case .today = range else {
            Issue.record("Expected .today (relative precedence), got \(String(describing: range))")
            return
        }
    }

    // MARK: - parseDateFilter: Absolute Dates

    @Test func parseAbsoluteFromAndTo() throws {
        let json: [String: Any] = ["from": "2026-02-01", "to": "2026-02-11"]
        let range = try DateFilterHelpers.parseDateFilter(json)
        guard case .absolute(let from, let endDate) = range else {
            Issue.record("Expected .absolute, got \(String(describing: range))")
            return
        }
        #expect(from != nil)
        #expect(endDate != nil)
    }

    @Test func parseAbsoluteFromOnly() throws {
        let json: [String: Any] = ["from": "2026-02-01"]
        let range = try DateFilterHelpers.parseDateFilter(json)
        guard case .absolute(let from, let endDate) = range else {
            Issue.record("Expected .absolute, got \(String(describing: range))")
            return
        }
        #expect(from != nil)
        #expect(endDate == nil)
    }

    @Test func parseAbsoluteToOnly() throws {
        let json: [String: Any] = ["to": "2026-02-11"]
        let range = try DateFilterHelpers.parseDateFilter(json)
        guard case .absolute(let from, let endDate) = range else {
            Issue.record("Expected .absolute, got \(String(describing: range))")
            return
        }
        #expect(from == nil)
        #expect(endDate != nil)
    }

    @Test func parseEmptyFilterReturnsNil() throws {
        let json: [String: Any] = [:]
        let range = try DateFilterHelpers.parseDateFilter(json)
        #expect(range == nil)
    }

    @Test func parseInvalidFromDateThrows() {
        let json: [String: Any] = ["from": "not-a-date"]
        #expect(throws: VisualIntentError.self) {
            try DateFilterHelpers.parseDateFilter(json)
        }
    }

    @Test func parseInvalidToDateThrows() {
        let json: [String: Any] = ["to": "2026-13-45"]
        #expect(throws: VisualIntentError.self) {
            try DateFilterHelpers.parseDateFilter(json)
        }
    }

    // MARK: - dateInRange: Today

    @Test func dateInRangeTodayIncludesNow() {
        #expect(DateFilterHelpers.dateInRange(Date(), range: .today))
    }

    @Test func dateInRangeTodayExcludesYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        #expect(!DateFilterHelpers.dateInRange(yesterday, range: .today))
    }

    // MARK: - dateInRange: This Week

    @Test func dateInRangeThisWeekIncludesToday() {
        #expect(DateFilterHelpers.dateInRange(Date(), range: .thisWeek))
    }

    @Test func dateInRangeThisWeekExcludesLastMonth() {
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        #expect(!DateFilterHelpers.dateInRange(lastMonth, range: .thisWeek))
    }

    // MARK: - dateInRange: This Month

    @Test func dateInRangeThisMonthIncludesToday() {
        #expect(DateFilterHelpers.dateInRange(Date(), range: .thisMonth))
    }

    @Test func dateInRangeThisMonthExcludesLastYear() {
        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        #expect(!DateFilterHelpers.dateInRange(lastYear, range: .thisMonth))
    }

    // MARK: - dateInRange: Absolute with from and to

    @Test func absoluteRangeIncludesDateWithinRange() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let mid = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        #expect(DateFilterHelpers.dateInRange(mid, range: .absolute(from: from, endDate: endDate)))
    }

    @Test func absoluteRangeIncludesBoundaryFromDate() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28))!
        #expect(DateFilterHelpers.dateInRange(from, range: .absolute(from: from, endDate: endDate)))
    }

    @Test func absoluteRangeIncludesBoundaryToDate() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28))!
        #expect(DateFilterHelpers.dateInRange(endDate, range: .absolute(from: from, endDate: endDate)))
    }

    @Test func absoluteRangeExcludesDateBeforeRange() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28))!
        let before = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        #expect(!DateFilterHelpers.dateInRange(before, range: .absolute(from: from, endDate: endDate)))
    }

    @Test func absoluteRangeExcludesDateAfterRange() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28))!
        let after = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        #expect(!DateFilterHelpers.dateInRange(after, range: .absolute(from: from, endDate: endDate)))
    }

    // MARK: - dateInRange: Absolute with from only

    @Test func absoluteFromOnlyIncludesDateOnOrAfter() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let after = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        #expect(DateFilterHelpers.dateInRange(after, range: .absolute(from: from, endDate: nil)))
    }

    @Test func absoluteFromOnlyExcludesDateBefore() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let before = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        #expect(!DateFilterHelpers.dateInRange(before, range: .absolute(from: from, endDate: nil)))
    }

    // MARK: - dateInRange: Absolute with to only

    @Test func absoluteToOnlyIncludesDateOnOrBefore() {
        let calendar = Calendar.current
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28))!
        let before = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        #expect(DateFilterHelpers.dateInRange(before, range: .absolute(from: nil, endDate: endDate)))
    }

    @Test func absoluteToOnlyExcludesDateAfter() {
        let calendar = Calendar.current
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28))!
        let after = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        #expect(!DateFilterHelpers.dateInRange(after, range: .absolute(from: nil, endDate: endDate)))
    }

    // MARK: - dateInRange: Day-level comparison (not timestamp)

    @Test func absoluteRangeUsesStartOfDayNormalization() {
        let calendar = Calendar.current
        let from = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        // A date on the same day but later in the day should still match
        let sameDayLater = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 1, hour: 23, minute: 59)
        )!
        #expect(DateFilterHelpers.dateInRange(sameDayLater, range: .absolute(from: from, endDate: endDate)))
    }

    // MARK: - Idempotence

    @Test func dateInRangeIsIdempotent() {
        let date = Date()
        let result1 = DateFilterHelpers.dateInRange(date, range: .today)
        let result2 = DateFilterHelpers.dateInRange(date, range: .today)
        #expect(result1 == result2)
    }
}
