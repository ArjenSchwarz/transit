//
//  ColumnView.swift
//  Transit
//
//  Single kanban column with header, task list, and empty state.
//

import SwiftData
import SwiftUI

struct ColumnView: View {
    let column: DashboardColumn
    let tasks: [TransitTask]
    let onTaskTap: (TransitTask) -> Void
    let onDrop: (UUID, DashboardColumn) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with column name and count
            HStack {
                Text(column.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(tasks.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial)
            .glassEffect()

            Divider()

            // Task list or empty state
            if tasks.isEmpty {
                EmptyStateView(message: "No tasks in \(column.displayName)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(tasks) { task in
                            // Insert separator between done and abandoned tasks
                            if column == .doneAbandoned && shouldShowSeparator(before: task) {
                                VStack(spacing: 8) {
                                    Divider()
                                    Text("Abandoned")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Divider()
                                }
                                .padding(.vertical, 8)
                            }

                            TaskCardView(task: task) {
                                onTaskTap(task)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: String.self) { uuids, _ in
            guard let uuidString = uuids.first,
                  let uuid = UUID(uuidString: uuidString) else {
                return false
            }
            return onDrop(uuid, column)
        }
    }

    /// Determines if separator should be shown before this task.
    /// Shows separator before the first abandoned task in the done/abandoned column.
    private func shouldShowSeparator(before task: TransitTask) -> Bool {
        guard column == .doneAbandoned else { return false }
        guard task.status == .abandoned else { return false }

        // Check if this is the first abandoned task
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            // All tasks before this should be done (not abandoned)
            return tasks[..<index].allSatisfy { $0.status != .abandoned }
        }
        return false
    }
}
