import SwiftUI

struct TaskCardView: View {
    let task: TransitTask

    @AppStorage("appTheme") private var appTheme: String = AppTheme.followSystem.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedTheme: ResolvedTheme {
        (AppTheme(rawValue: appTheme) ?? .followSystem).resolved(with: colorScheme)
    }

    private var projectColor: Color {
        guard let hex = task.project?.colorHex else { return .gray }
        return Color(hex: hex)
    }

    private var isAbandoned: Bool {
        task.status == .abandoned
    }

    private var accessibilityID: String {
        if let displayID = task.permanentDisplayId {
            return "dashboard.taskCard.\(displayID)"
        }
        return "dashboard.taskCard.provisional"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Project name (secondary)
            Text(task.project?.name ?? "Unknown")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Task name + display ID
            HStack(alignment: .top) {
                Text(task.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(isAbandoned)

                Spacer()

                Text(task.displayID.formatted)
                    .font(.caption)
                    .foregroundStyle(
                        task.displayID == .provisional ? .secondary : .primary
                    )
            }

            // Badges row
            HStack(spacing: 6) {
                if task.status.isHandoff {
                    Label("Handoff", systemImage: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                }

                TypeBadge(type: task.type)

                if let count = task.comments?.count, count > 0 {
                    Label("\(count)", systemImage: "bubble.left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(cardMaterial)
        }
        .overlay(alignment: .top) {
            // Top-edge accent stripe (project colour)
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 12
            )
            .fill(projectColor)
            .frame(height: 2.5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(cardBorder, lineWidth: 0.5)
        )
        .shadow(color: cardShadow, radius: cardShadowRadius, y: cardShadowY)
        .opacity(isAbandoned ? 0.5 : 1.0)
        .draggable(task.id.uuidString) // [req 7.1]
        .accessibilityIdentifier(accessibilityID)
    }

    // MARK: - Theme-Adapted Card Styling

    private var cardMaterial: Material {
        switch resolvedTheme {
        case .universal: .ultraThinMaterial
        case .light: .thinMaterial
        case .dark: .ultraThinMaterial
        }
    }

    private var cardBorder: Color {
        switch resolvedTheme {
        case .universal: .white.opacity(0.15)
        case .light: .white.opacity(0.5)
        case .dark: .white.opacity(0.10)
        }
    }

    private var cardShadow: Color {
        switch resolvedTheme {
        case .universal: .black.opacity(0.08)
        case .light: .black.opacity(0.06)
        case .dark: .black.opacity(0.20)
        }
    }

    private var cardShadowRadius: CGFloat {
        resolvedTheme == .light ? 4 : 2
    }

    private var cardShadowY: CGFloat {
        resolvedTheme == .light ? 2 : 1
    }
}
