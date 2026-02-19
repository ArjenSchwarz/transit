import Foundation

@MainActor
enum DateFilterHelpers {
    enum DateRange: Equatable {
        case today
        case yesterday
        case thisWeek
        case lastWeek
        case thisMonth
        case lastMonth
        case thisYear
        case lastYear
        case absolute(from: Date?, toDate: Date?)
    }

    private static let localDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let relativeTokens: [String: DateRange] = [
        "today": .today,
        "yesterday": .yesterday,
        "this-week": .thisWeek,
        "last-week": .lastWeek,
        "this-month": .thisMonth,
        "last-month": .lastMonth,
        "this-year": .thisYear,
        "last-year": .lastYear
    ]

    static func parseDateFilter(_ json: [String: Any]) -> DateRange? {
        parseDateFilter(
            relative: json["relative"] as? String,
            from: json["from"] as? String,
            toDateString: json["to"] as? String
        )
    }

    static func parseDateFilter(
        relative: String?,
        from: String?,
        toDateString: String?
    ) -> DateRange? {
        if let relative {
            return relativeTokens[relative]
        }

        let fromDate = from.flatMap(dateFromString)
        let toDate = toDateString.flatMap(dateFromString)

        if from != nil && fromDate == nil { return nil }
        if toDateString != nil && toDate == nil { return nil }

        if from != nil || toDateString != nil {
            return .absolute(from: fromDate, toDate: toDate)
        }

        return nil
    }

    static func dateInRange(_ date: Date, range: DateRange, now: Date = Date()) -> Bool {
        let calendar = Calendar.current

        switch range {
        case .today:
            return calendar.isDate(date, inSameDayAs: now)

        case .yesterday:
            let startOfToday = calendar.startOfDay(for: now)
            guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
                return false
            }
            return date >= startOfYesterday && date < startOfToday

        case .thisWeek:
            return dateInCurrentPeriod(date, component: .weekOfYear, now: now, calendar: calendar)

        case .lastWeek:
            return dateInPreviousPeriod(date, component: .weekOfYear, now: now, calendar: calendar)

        case .thisMonth:
            return dateInCurrentPeriod(date, component: .month, now: now, calendar: calendar)

        case .lastMonth:
            return dateInPreviousPeriod(date, component: .month, now: now, calendar: calendar)

        case .thisYear:
            return dateInCurrentPeriod(date, component: .year, now: now, calendar: calendar)

        case .lastYear:
            return dateInPreviousPeriod(date, component: .year, now: now, calendar: calendar)

        case .absolute(let from, let toDate):
            return dateInAbsoluteRange(date, from: from, toDate: toDate, calendar: calendar)
        }
    }

    /// "This X" ranges: from start of current period to now (inclusive).
    private static func dateInCurrentPeriod(
        _ date: Date, component: Calendar.Component, now: Date, calendar: Calendar
    ) -> Bool {
        guard let interval = calendar.dateInterval(of: component, for: now) else { return false }
        return date >= interval.start && date <= now
    }

    /// "Last X" ranges: full previous period with exclusive upper bound.
    private static func dateInPreviousPeriod(
        _ date: Date, component: Calendar.Component, now: Date, calendar: Calendar
    ) -> Bool {
        guard let previousDate = calendar.date(byAdding: component, value: -1, to: now),
              let interval = calendar.dateInterval(of: component, for: previousDate) else {
            return false
        }
        return date >= interval.start && date < interval.end
    }

    private static func dateInAbsoluteRange(
        _ date: Date, from: Date?, toDate: Date?, calendar: Calendar
    ) -> Bool {
        let day = calendar.startOfDay(for: date)

        if let from {
            let start = calendar.startOfDay(for: from)
            if day < start { return false }
        }

        if let toDate {
            let end = calendar.startOfDay(for: toDate)
            if day > end { return false }
        }

        return true
    }

    private static func dateFromString(_ value: String) -> Date? {
        localDayFormatter.date(from: value)
    }
}
