import Foundation

/// Represents either a permanent or provisional display ID.
enum DisplayID: Equatable, Sendable {
    case permanent(Int)
    case provisional

    /// Formatted string for UI display. [req 3.6, 3.7]
    nonisolated var formatted: String {
        switch self {
        case .permanent(let id): "T-\(id)"
        case .provisional: "T-\u{2022}"
        }
    }
}
