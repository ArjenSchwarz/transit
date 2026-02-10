import SwiftUI

struct ColumnView: View {
    let column: DashboardColumn
    let tasks: [TransitTask]
    let onDropTask: (_ taskID: UUID, _ column: DashboardColumn) -> Bool

    private var firstAbandonedIndex: Int? {
        guard column == .doneAbandoned else {
            return nil
        }

        return tasks.firstIndex(where: { $0.status == .abandoned })
    }

    private var emptyMessage: String {
        "No tasks in \(column.displayName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(column.displayName)
                    .font(.headline)

                Spacer(minLength: 8)

                Text("\(tasks.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.clear)
                    .glassEffect()
            }

            if tasks.isEmpty {
                EmptyStateView(message: emptyMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            if let firstAbandonedIndex, index == firstAbandonedIndex {
                                Divider()
                                    .overlay(alignment: .center) {
                                        Text("Abandoned")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .background(.background)
                                    }
                            }

                            TaskCardView(task: task)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
                .glassEffect()
        }
        .dropDestination(for: TaskDragPayload.self) { payloads, _ in
            guard let payload = payloads.first else {
                return false
            }
            return onDropTask(payload.taskID, column)
        }
    }
}
