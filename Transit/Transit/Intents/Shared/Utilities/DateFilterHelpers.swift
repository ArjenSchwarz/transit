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

        let fromDate = from.flatMap(dateFromString)
        let toDate = toDateString.flatMap(dateFromString)

        if from != nil && fromDate == nil {
            return nil
        }
        if toDateString != nil && toDate == nil {
            return nil
        }

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
