import Foundation

extension Date {
    nonisolated static let fortyEightHours: TimeInterval = 48 * 60 * 60

    nonisolated func isWithinLast48Hours(referenceDate: Date = .now) -> Bool {
        self > referenceDate.addingTimeInterval(-Self.fortyEightHours)
    }
}
