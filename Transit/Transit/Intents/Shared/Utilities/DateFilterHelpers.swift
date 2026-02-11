import Foundation

@MainActor
enum DateFilterHelpers {
    enum DateRange {
        case today
        case thisWeek
        case thisMonth
        case absolute(from: Date?, to: Date?)
    }

    /// Parse JSON date filter into DateRange
    static func parseDateFilter(_ json: [String: Any]) -> DateRange? {
        if let relative = json["relative"] as? String {
            switch relative {
            case "today": return .today
            case "this-week": return .thisWeek
            case "this-month": return .thisMonth
            default: return nil
            }
        }

        if let fromString = json["from"] as? String,
           let toString = json["to"] as? String {
            let from = dateFromString(fromString)
            let to = dateFromString(toString)
            return .absolute(from: from, to: to)
        }

        if let fromString = json["from"] as? String {
            return .absolute(from: dateFromString(fromString), to: nil)
        }

        if let toString = json["to"] as? String {
            return .absolute(from: nil, to: dateFromString(toString))
        }

        return nil
    }

    /// Check if a date falls within a range
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

        case .absolute(let from, let to):
            let normalizedDate = calendar.startOfDay(for: date)

            if let from, let to {
                let normalizedFrom = calendar.startOfDay(for: from)
                let normalizedTo = calendar.startOfDay(for: to)
                return normalizedDate >= normalizedFrom && normalizedDate <= normalizedTo
            }

            if let from {
                let normalizedFrom = calendar.startOfDay(for: from)
                return normalizedDate >= normalizedFrom
            }

            if let to {
                let normalizedTo = calendar.startOfDay(for: to)
                return normalizedDate <= normalizedTo
            }

            return true
        }
    }

    /// Convert YYYY-MM-DD string to Date in local timezone
    private static func dateFromString(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        return formatter.date(from: string)
    }
}
