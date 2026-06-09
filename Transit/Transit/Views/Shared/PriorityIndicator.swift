import SwiftUI

/// Board-card priority glyph. Renders a bare SF Symbol for high/low and nothing
/// for medium. Suppression is read from `TaskPriority.glyphSymbol` (nil for
/// medium, the single source of truth — Decision 6), not re-decided here.
struct PriorityIndicator: View {
    let priority: TaskPriority

    var body: some View {
        if let symbol = priority.glyphSymbol {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(priority.tintColor)
                .accessibilityLabel(priority.accessibilityLabel)
                .accessibilityIdentifier("dashboard.taskCard.priority")
        }
    }
}
