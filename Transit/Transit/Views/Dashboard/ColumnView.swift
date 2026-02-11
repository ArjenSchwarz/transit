import SwiftUI

struct ColumnView: View {
    let column: DashboardColumn
    let tasks: [TransitTask]
    let onTaskTap: (TransitTask) -> Void
    var onDrop: ((String) -> Bool)? // UUID string of dropped task

    @AppStorage("appTheme") private var appTheme: String = AppTheme.followSystem.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false

    private var resolvedTheme: ResolvedTheme {
        (AppTheme(rawValue: appTheme) ?? .followSystem).resolved(with: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with name and count [req 5.9]
            HStack {
                Text(column.displayName)
                    .font(.headline)
                Spacer()
                Text("\(tasks.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 8)

            if tasks.isEmpty {
                // Per-column empty state [req 20.2]
                Spacer()
                EmptyStateView(message: "No tasks in \(column.displayName)")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(tasks, id: \.id) { task in
                            // Insert separator before first abandoned task [req 5.5]
                            if column == .doneAbandoned && task.status == .abandoned {
                                if isFirstAbandoned(task) {
                                    abandonedSeparator
                                }
                            }

                            TaskCardView(task: task)
                                .onTapGesture { onTaskTap(task) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
        .contentShape(.rect)
        .background {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.tint.opacity(0.1))
            } else {
                columnPanel
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first else { return false }
            return onDrop?(uuidString) ?? false
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                isDropTargeted = targeted
            }
        }
    }

    // MARK: - Column Panel

    @ViewBuilder
    private var columnPanel: some View {
        switch resolvedTheme {
        case .universal:
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
        case .light:
            RoundedRectangle(cornerRadius: 14)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.4), lineWidth: 0.5)
                )
        case .dark:
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.black.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }

    /// Whether this task is the first abandoned task in the list.
    /// Tasks are pre-sorted: done first, then abandoned [req 5.5].
    private func isFirstAbandoned(_ task: TransitTask) -> Bool {
        tasks.first(where: { $0.status == .abandoned })?.id == task.id
    }

    private var abandonedSeparator: some View {
        HStack {
            VStack { Divider() }
            Text("Abandoned")
                .font(.caption2)
                .foregroundStyle(.secondary)
            VStack { Divider() }
        }
        .padding(.vertical, 4)
    }
}
