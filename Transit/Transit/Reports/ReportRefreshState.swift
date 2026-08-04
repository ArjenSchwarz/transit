import Foundation

/// Calculates the next boundary at which a relative report can change.
struct ReportRefreshScheduler {
    static func nextRefreshDate(
        for dateRange: ReportDateRange,
        now: Date,
        calendar: Calendar
    ) -> Date {
        let component: Calendar.Component

        switch dateRange {
        case .today, .yesterday, .thisWeek, .thisMonth, .thisYear:
            // Current periods end at `now`, and their labels show the current day.
            component = .day
        case .lastWeek:
            component = .weekOfYear
        case .lastMonth:
            component = .month
        case .lastYear:
            component = .year
        }

        guard let interval = calendar.dateInterval(of: component, for: now) else {
            preconditionFailure("Calendar could not calculate the next report refresh boundary")
        }
        return interval.end
    }
}

/// Owns the single time and calendar snapshot used for one visible report render.
struct ReportRefreshState {
    private let clock: () -> Date
    private let calendarProvider: () -> Calendar

    private(set) var now: Date
    private(set) var calendar: Calendar
    private(set) var refreshGeneration = 0

    init(
        clock: @escaping () -> Date = { .now },
        calendar: @escaping () -> Calendar = { .current }
    ) {
        self.clock = clock
        calendarProvider = calendar
        now = clock()
        self.calendar = calendar()
    }

    mutating func refresh() {
        now = clock()
        calendar = calendarProvider()
        refreshGeneration &+= 1
    }

    func nextRefreshDate(for dateRange: ReportDateRange) -> Date {
        ReportRefreshScheduler.nextRefreshDate(
            for: dateRange,
            now: now,
            calendar: calendar
        )
    }
}
