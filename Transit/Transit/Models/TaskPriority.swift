import SwiftUI

enum TaskPriority: String, Codable, CaseIterable {
    case low
    case medium
    case high

    /// Order for pickers and the filter menu: most actionable value first.
    /// `allCases` is source order (low-first); display surfaces iterate this
    /// instead so high reads first.
    static let displayOrder: [TaskPriority] = [.high, .medium, .low]

    /// Color used for the filter dot (all three) and the card glyph (low/high).
    var tintColor: Color {
        switch self {
        case .high: .red
        case .medium: .orange
        case .low: .blue
        }
    }

    /// SF Symbol shown on the board card. `nil` for medium is the single source
    /// of truth for "no card glyph" (Decision 6); the card reads it rather than
    /// re-deciding suppression.
    var glyphSymbol: String? {
        switch self {
        case .high: "arrow.up.circle.fill"
        case .medium: nil
        case .low: "arrow.down.circle.fill"
        }
    }

    /// VoiceOver label naming the priority level (e.g. "High priority").
    var accessibilityLabel: String {
        switch self {
        case .high: "High priority"
        case .medium: "Medium priority"
        case .low: "Low priority"
        }
    }
}
