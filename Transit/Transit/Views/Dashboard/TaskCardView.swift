import SwiftUI

struct TaskCardView: View {
    let task: TransitTask

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
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(projectColor, lineWidth: 1.5)
        )
        .opacity(isAbandoned ? 0.5 : 1.0)
        .draggable(task.id.uuidString) // [req 7.1]
        .accessibilityIdentifier(accessibilityID)
    }
}
