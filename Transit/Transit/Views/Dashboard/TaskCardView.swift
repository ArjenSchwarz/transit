import SwiftUI

struct TaskCardView: View {
    let task: TransitTask

    private var projectColor: Color {
        guard let hex = task.project?.colorHex else { return .gray }
        return Color(hex: hex)
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
                    .strikethrough(task.status == .abandoned)

                Spacer()

                Text(task.displayID.formatted)
                    .font(.caption)
                    .foregroundStyle(
                        task.displayID == .provisional ? .secondary : .primary
                    )
            }

            // Type badge
            TypeBadge(type: task.type)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(projectColor, lineWidth: 1.5)
        )
        .opacity(task.status == .abandoned ? 0.5 : 1.0)
        .draggable(task.id.uuidString) // [req 7.1]
    }
}
