import Foundation

/// Represents either a permanent or provisional display ID.
enum DisplayID: Equatable, Sendable {
    case permanent(Int)
    case provisional

    /// Formatted string for UI display. [req 3.6, 3.7]
    nonisolated var formatted: String {
        formatted(prefix: "T")
    }

    /// Formatted string with a custom prefix (e.g. "M" for milestones).
    nonisolated func formatted(prefix: String) -> String {
        switch self {
        case .permanent(let id): "\(prefix)-\(id)"
        case .provisional: "\(prefix)-\u{2022}"
        }
    }
}
