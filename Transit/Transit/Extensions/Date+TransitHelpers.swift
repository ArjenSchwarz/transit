import Foundation

extension Date {
    /// Whether this date is within the last 48 hours relative to the given reference date.
    func isWithin48Hours(of reference: Date = .now) -> Bool {
        reference.timeIntervalSince(self) <= 48 * 60 * 60
    }
}
