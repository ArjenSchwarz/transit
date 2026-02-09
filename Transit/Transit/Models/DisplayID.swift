//
//  DisplayID.swift
//  Transit
//
//  Display ID representation for tasks (permanent or provisional).
//

import Foundation

/// Represents either a permanent or provisional display ID.
/// Permanent IDs are allocated from CloudKit counter.
/// Provisional IDs are assigned offline and promoted when connectivity returns.
enum DisplayID: Codable, Equatable, Sendable {
    case permanent(Int)
    case provisional

    /// Formatted string for UI display.
    /// Permanent: "T-{number}" (e.g., T-1, T-42)
    /// Provisional: "T-•" (indicates pending sync)
    var formatted: String {
        switch self {
        case .permanent(let id):
            return "T-\(id)"
        case .provisional:
            return "T-•"
        }
    }
}
