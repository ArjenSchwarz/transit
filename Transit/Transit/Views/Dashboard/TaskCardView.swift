import SwiftUI

struct TaskCardView: View {
    let task: TransitTask
    let onSelect: () -> Void

    private var projectName: String {
        task.project?.name ?? "Unknown Project"
    }

    private var projectBorderColor: Color {
        task.project?.color ?? .secondary.opacity(0.35)
    }

    private var isAbandoned: Bool {
        task.status == .abandoned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(projectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(task.displayID.formatted)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(task.permanentDisplayId == nil ? .secondary : .primary)
            }

            Text(task.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .strikethrough(isAbandoned, pattern: .solid, color: .primary)

            HStack(spacing: 6) {
                if task.status.isHandoff {
                    Label("Handoff", systemImage: "exclamationmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.16), in: Capsule(style: .continuous))
                }

                TypeBadge(type: task.type)

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.clear)
                .glassEffect()
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(projectBorderColor, lineWidth: 1.5)
        }
        .opacity(isAbandoned ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onSelect)
        .draggable(TaskDragPayload(taskID: task.id))
    }
}
