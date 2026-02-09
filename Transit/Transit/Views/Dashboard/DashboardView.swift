import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \TransitTask.lastStatusChangeDate, order: .reverse) private var allTasks: [TransitTask]
    @Query private var projects: [Project]
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var selectedColumn: DashboardColumn = .inProgress // [req 13.3]
    @State private var selectedTask: TransitTask?
    @State private var showFilter = false
    @Environment(TaskService.self) private var taskService
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Minimum width (in points) for a single kanban column.
    private static let columnMinWidth: CGFloat = 200

    private var isPhoneLandscape: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        GeometryReader { geometry in
            let rawColumnCount = max(1, Int(geometry.size.width / Self.columnMinWidth))
            let columnCount = isPhoneLandscape ? min(rawColumnCount, 3) : rawColumnCount

            if columnCount == 1 {
                SingleColumnView(
                    columns: filteredColumns,
                    selectedColumn: $selectedColumn,
                    onTaskTap: { selectedTask = $0 },
                    onDrop: handleDrop
                )
            } else {
                KanbanBoardView(
                    columns: filteredColumns,
                    visibleCount: min(columnCount, 5),
                    initialScrollTarget: isPhoneLandscape ? .planning : nil,
                    onTaskTap: { selectedTask = $0 },
                    onDrop: handleDrop
                )
            }
        }
        .overlay {
            if allTasks.isEmpty {
                EmptyStateView(message: "No tasks yet. Tap + to create one.")
            }
        }
        .navigationTitle("Transit")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                filterButton
                addButton
            }
            ToolbarItem(placement: .secondaryAction) {
                NavigationLink(value: "settings") {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .sheet(item: $selectedTask) { task in
            Text("Task: \(task.name)") // Placeholder — TaskDetailView comes in a later phase
        }
    }

    // MARK: - Toolbar Buttons

    private var filterButton: some View {
        Button {
            showFilter.toggle()
        } label: {
            if selectedProjectIDs.isEmpty {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                Label("Filter (\(selectedProjectIDs.count))", systemImage: "line.3.horizontal.decrease.circle.fill")
            }
        }
        .popover(isPresented: $showFilter) {
            FilterPopoverView(
                projects: projects,
                selectedProjectIDs: $selectedProjectIDs
            )
        }
    }

    private var addButton: some View {
        Button {
            // AddTaskSheet comes in a later phase
        } label: {
            Label("Add Task", systemImage: "plus")
        }
    }

    // MARK: - Drag and Drop

    /// Handles a task drop onto a column. [req 7.1-7.5]
    private func handleDrop(column: DashboardColumn, uuidString: String) -> Bool {
        guard let uuid = UUID(uuidString: uuidString),
              let task = allTasks.first(where: { $0.id == uuid }) else {
            return false
        }
        let targetStatus = column.primaryStatus // [req 7.2, 7.4] — Done/Abandoned maps to .done
        taskService.updateStatus(task: task, to: targetStatus)
        return true
    }

    // MARK: - Column Filtering & Sorting

    /// Tasks grouped by column, filtered by project selection, with sorting applied.
    var filteredColumns: [DashboardColumn: [TransitTask]] {
        Self.buildFilteredColumns(
            allTasks: allTasks,
            selectedProjectIDs: selectedProjectIDs
        )
    }

    /// Testable, static column builder.
    static func buildFilteredColumns(
        allTasks: [TransitTask],
        selectedProjectIDs: Set<UUID>,
        now: Date = .now
    ) -> [DashboardColumn: [TransitTask]] {
        let filtered: [TransitTask]
        if selectedProjectIDs.isEmpty {
            filtered = allTasks.filter { $0.project != nil }
        } else {
            filtered = allTasks.filter { task in
                guard let projectId = task.project?.id else { return false }
                return selectedProjectIDs.contains(projectId)
            }
        }

        let cutoff = now.addingTimeInterval(-48 * 60 * 60)

        var grouped = Dictionary(grouping: filtered) { $0.status.column }

        // Ensure all columns exist (even if empty)
        for column in DashboardColumn.allCases where grouped[column] == nil {
            grouped[column] = []
        }

        return grouped.mapValues { tasks in
            tasks.filter { task in
                if task.status.isTerminal {
                    // Defensive: nil completionDate treated as just-completed [req 5.6]
                    return (task.completionDate ?? now) > cutoff
                }
                return true
            }
            .sorted { lhs, rhs in
                // Done before abandoned in terminal column [req 5.5]
                if lhs.status == .abandoned != (rhs.status == .abandoned) {
                    return rhs.status == .abandoned
                }
                // Handoff tasks first within their column [req 5.3, 5.4]
                if lhs.status.isHandoff != rhs.status.isHandoff {
                    return lhs.status.isHandoff
                }
                // Then by date descending [req 5.8]
                return lhs.lastStatusChangeDate > rhs.lastStatusChangeDate
            }
        }
    }
}

// MARK: - Identifiable for sheet presentation

extension TransitTask: @retroactive Identifiable {}
