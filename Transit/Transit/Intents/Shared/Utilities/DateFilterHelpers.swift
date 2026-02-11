import Foundation

@MainActor
enum DateFilterHelpers {
    enum DateRange: Equatable {
        case today
        case thisWeek
        case thisMonth
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

    static func parseDateFilter(_ json: [String: Any]) -> DateRange? {
        if let relative = json["relative"] as? String {
            switch relative {
            case "today":
                return .today
            case "this-week":
                return .thisWeek
            case "this-month":
                return .thisMonth
            default:
                return nil
            }
        }

        let from = (json["from"] as? String).flatMap(dateFromString)
        let toDate = (json["to"] as? String).flatMap(dateFromString)

        if json["from"] != nil && from == nil {
            return nil
        }
        if json["to"] != nil && toDate == nil {
            return nil
        }

        if json["from"] != nil || json["to"] != nil {
            return .absolute(from: from, toDate: toDate)
        }

        return nil
    }

    static func dateInRange(_ date: Date, range: DateRange, now: Date = Date()) -> Bool {
        let calendar = Calendar.current

        switch range {
        case .today:
            return calendar.isDate(date, inSameDayAs: now)

        case .thisWeek:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
                return false
            }
            return date >= week.start && date <= now

        case .thisMonth:
            guard let month = calendar.dateInterval(of: .month, for: now) else {
                return false
            }
            return date >= month.start && date <= now

        case .absolute(let from, let toDate):
            let day = calendar.startOfDay(for: date)

            if let from {
                let start = calendar.startOfDay(for: from)
                if day < start {
                    return false
                }
            }

            if let toDate {
                let end = calendar.startOfDay(for: toDate)
                if day > end {
                    return false
                }
            }

            return true
        }
    }

    private static func dateFromString(_ value: String) -> Date? {
        localDayFormatter.date(from: value)
    }
}
