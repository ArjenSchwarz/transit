import Foundation

nonisolated struct BackupSchedule: Equatable {
    var hour: Int
    var minute: Int

    // A neutral UTC anchor represents wall-clock fields only, independent of today's DST gap.
    static let pickerTimeZone = TimeZone(secondsFromGMT: 0)!

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(pickerDate: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.pickerTimeZone
        hour = calendar.component(.hour, from: pickerDate)
        minute = calendar.component(.minute, from: pickerDate)
    }

    var pickerDate: Date {
        Date(timeIntervalSinceReferenceDate: Double(hour * 3600 + minute * 60))
    }

    func latestDue(before now: Date, calendar: Calendar = .current) -> Date? {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        let start = calendar.startOfDay(for: now)
        func due(on day: Date) -> Date? {
            calendar.nextDate(
                after: day.addingTimeInterval(-1), matching: DateComponents(hour: hour, minute: minute),
                matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }
        if let today = due(on: start), today <= now { return today }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: start) else { return nil }
        return due(on: yesterday)
    }

    func isDue(now: Date, lastSuccess: Date?, enabledAt: Date, calendar: Calendar = .current)
        -> Bool {
        guard let due = latestDue(before: now, calendar: calendar), due >= enabledAt else {
            return false
        }
        return lastSuccess.map { $0 < due } ?? true
    }
}
