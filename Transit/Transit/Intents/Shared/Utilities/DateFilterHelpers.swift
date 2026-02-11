import Foundation

enum DateFilterHelpers {
    enum DateRange {
        case today
        case thisWeek
        case thisMonth
        case absolute(from: Date?, endDate: Date?)
    }

    /// Parse a JSON date filter object into a DateRange.
    /// Returns nil if the filter is empty or contains no recognized keys.
    /// Throws VisualIntentError.invalidDate for malformed date strings.
    static func parseDateFilter(_ json: [String: Any]) throws -> DateRange? {
        // Relative takes precedence per Decision 20
        if let relative = json["relative"] as? String {
            switch relative {
            case "today": return .today
            case "this-week": return .thisWeek
            case "this-month": return .thisMonth
            default:
                throw VisualIntentError.invalidDate("Unknown relative date: \(relative)")
            }
        }

        let fromString = json["from"] as? String
        let toString = json["to"] as? String

        guard fromString != nil || toString != nil else {
            return nil
        }

        var fromDate: Date?
        var toDate: Date?

        if let fromString {
            guard let date = dateFromString(fromString) else {
                throw VisualIntentError.invalidDate("Invalid 'from' date: \(fromString). Expected YYYY-MM-DD.")
            }
            fromDate = date
        }

        if let toString {
            guard let date = dateFromString(toString) else {
                throw VisualIntentError.invalidDate("Invalid 'to' date: \(toString). Expected YYYY-MM-DD.")
            }
            toDate = date
        }

        return .absolute(from: fromDate, endDate: toDate)
    }

    /// Check if a date falls within a range using Calendar.current.
    static func dateInRange(_ date: Date, range: DateRange) -> Bool {
        let calendar = Calendar.current

        switch range {
        case .today:
            return calendar.isDateInToday(date)

        case .thisWeek:
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
                return false
            }
            return date >= weekInterval.start && date <= Date()

        case .thisMonth:
            guard let monthInterval = calendar.dateInterval(of: .month, for: Date()) else {
                return false
            }
            return date >= monthInterval.start && date <= Date()

        case .absolute(let from, let endDate):
            let normalizedDate = calendar.startOfDay(for: date)

            if let from, let endDate {
                let normalizedFrom = calendar.startOfDay(for: from)
                let normalizedEnd = calendar.startOfDay(for: endDate)
                return normalizedDate >= normalizedFrom && normalizedDate <= normalizedEnd
            }

            if let from {
                let normalizedFrom = calendar.startOfDay(for: from)
                return normalizedDate >= normalizedFrom
            }

            if let endDate {
                let normalizedEnd = calendar.startOfDay(for: endDate)
                return normalizedDate <= normalizedEnd
            }

            return true
        }
    }

    /// Convert YYYY-MM-DD string to Date in the user's local timezone.
    private static func dateFromString(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        return formatter.date(from: string)
    }
}
