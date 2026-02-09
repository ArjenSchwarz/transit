//
//  Date+TransitHelpers.swift
//  Transit
//
//  Date helpers for Transit-specific logic.
//

import Foundation

extension Date {
    /// Check if this date is within the last 48 hours from now.
    /// Used to filter Done/Abandoned tasks on the dashboard.
    func isWithinLast48Hours(from now: Date = .now) -> Bool {
        let hoursDifference = now.timeIntervalSince(self) / 3600
        return hoursDifference >= 0 && hoursDifference <= 48
    }
}
