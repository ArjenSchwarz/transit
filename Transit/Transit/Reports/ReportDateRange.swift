import AppIntents

enum ReportDateRange: String, AppEnum, CaseIterable, Identifiable {
    case today = "today"
    case yesterday = "yesterday"
    case thisWeek = "this-week"
    case lastWeek = "last-week"
    case thisMonth = "this-month"
    case lastMonth = "last-month"
    case thisYear = "this-year"
    case lastYear = "last-year"

    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Date Range")
    }

    nonisolated static var caseDisplayRepresentations: [ReportDateRange: DisplayRepresentation] {
        [
            .today: "Today",
            .yesterday: "Yesterday",
            .thisWeek: "This Week",
            .lastWeek: "Last Week",
            .thisMonth: "This Month",
            .lastMonth: "Last Month",
            .thisYear: "This Year",
            .lastYear: "Last Year"
        ]
    }

    var id: String { rawValue }

    var label: String {
        guard let representation = Self.caseDisplayRepresentations[self] else {
            assertionFailure("Missing display representation for \(self)")
            return rawValue
        }
        return String(localized: representation.title)
    }

    var dateRange: DateFilterHelpers.DateRange {
        switch self {
        case .today: .today
        case .yesterday: .yesterday
        case .thisWeek: .thisWeek
        case .lastWeek: .lastWeek
        case .thisMonth: .thisMonth
        case .lastMonth: .lastMonth
        case .thisYear: .thisYear
        case .lastYear: .lastYear
        }
    }

    /// Returns the label with actual dates, e.g. "This Week (Feb 17 – 19, 2026)".
    func labelWithDates(now: Date = .now) -> String {
        let calendar = Calendar.current

        let (start, end) = dateInterval(now: now, calendar: calendar)

        if calendar.isDate(start, inSameDayAs: end) {
            return "\(label) (\(start.formatted(.dateTime.month(.abbreviated).day().year())))"
        }

        let formatted = (start ..< end).formatted(
            .interval.month(.abbreviated).day().year()
        )
        return "\(label) (\(formatted))"
    }

    private func dateInterval(now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        switch self {
        case .today:
            return (now, now)

        case .yesterday:
            let startOfToday = calendar.startOfDay(for: now)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
            return (yesterday, yesterday)

        case .thisWeek:
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)!
            return (interval.start, now)

        case .lastWeek:
            let previousDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
            let interval = calendar.dateInterval(of: .weekOfYear, for: previousDate)!
            let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end)!
            return (interval.start, lastDay)

        case .thisMonth:
            let interval = calendar.dateInterval(of: .month, for: now)!
            return (interval.start, now)

        case .lastMonth:
            let previousDate = calendar.date(byAdding: .month, value: -1, to: now)!
            let interval = calendar.dateInterval(of: .month, for: previousDate)!
            let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end)!
            return (interval.start, lastDay)

        case .thisYear:
            let interval = calendar.dateInterval(of: .year, for: now)!
            return (interval.start, now)

        case .lastYear:
            let previousDate = calendar.date(byAdding: .year, value: -1, to: now)!
            let interval = calendar.dateInterval(of: .year, for: previousDate)!
            let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end)!
            return (interval.start, lastDay)
        }
    }
}
