import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \TransitTask.lastStatusChangeDate, order: .reverse) private var allTasks: [TransitTask]
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var selectedTypes: Set<TaskType> = []
    @State private var selectedColumn: DashboardColumn = .inProgress // [req 13.3]
    @State private var selectedTask: TransitTask?
    @State private var showFilter = false
    @State private var showAddTask = false
    @AppStorage("appTheme") private var appTheme: String = AppTheme.followSystem.rawValue
    @Environment(TaskService.self) private var taskService
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    /// Minimum width (in points) for a single kanban column.
    private static let columnMinWidth: CGFloat = 200

    private var resolvedTheme: ResolvedTheme {
        (AppTheme(rawValue: appTheme) ?? .followSystem).resolved(with: colorScheme)
    }

    private var isPhoneLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var filteredColumns: [DashboardColumn: [TransitTask]] {
        DashboardLogic.buildFilteredColumns(
            allTasks: allTasks,
            selectedProjectIDs: selectedProjectIDs,
            selectedTypes: selectedTypes
        )
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
        .background {
            BoardBackground(theme: resolvedTheme)
        }
        .overlay {
            if allTasks.isEmpty {
                EmptyStateView(message: "No tasks yet. Tap + to create one.")
            }
        }
        .navigationTitle("Transit")
        .toolbarTitleDisplayMode(.inline)
        #if os(macOS)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                filterButton
                addButton
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: NavigationDestination.report) {
                    Label("Report", systemImage: "chart.bar.doc.horizontal")
                }
                .accessibilityIdentifier("dashboard.reportButton")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: NavigationDestination.settings) {
                    Label("Settings", systemImage: "gear")
                }
                .accessibilityIdentifier("dashboard.settingsButton")
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task, dismissAll: { selectedTask = nil })
        }
        .sheet(isPresented: $showAddTask) {
            AddTaskSheet()
        }
    }

    // MARK: - Toolbar Buttons

    private var activeFilterCount: Int {
        selectedProjectIDs.count + selectedTypes.count
    }

    private var activeFilterAccessibilityValue: String {
        "\(activeFilterCount) active filter\(activeFilterCount == 1 ? "" : "s")"
    }

    private var filterButton: some View {
        Button {
            showFilter.toggle()
        } label: {
            if activeFilterCount == 0 {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                Label("Filter (\(activeFilterCount))", systemImage: "line.3.horizontal.decrease.circle.fill")
            }
        }
        .accessibilityIdentifier("dashboard.filterButton")
        .accessibilityValue(activeFilterAccessibilityValue)
        .popover(isPresented: $showFilter) {
            FilterPopoverView(
                projects: projects,
                selectedProjectIDs: $selectedProjectIDs,
                selectedTypes: $selectedTypes
            )
        }
    }

    private var addButton: some View {
        Button {
            showAddTask = true
        } label: {
            Label("Add Task", systemImage: "plus")
        }
        .accessibilityIdentifier("dashboard.addButton")
    }

    // MARK: - Drag and Drop

    /// Handles a task drop onto a column. [req 7.1-7.5]
    private func handleDrop(column: DashboardColumn, uuidString: String) -> Bool {
        guard let uuid = UUID(uuidString: uuidString),
              let task = allTasks.first(where: { $0.id == uuid }) else {
            return false
        }
        do {
            try DashboardLogic.applyDrop(task: task, to: column, using: taskService)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Dashboard Logic (pure, testable)

enum DashboardLogic {

    /// Testable column builder: groups tasks by column, applies project and type filters,
    /// 48-hour cutoff for terminal tasks, and sorting rules.
    static func buildFilteredColumns(
        allTasks: [TransitTask],
        selectedProjectIDs: Set<UUID>,
        selectedTypes: Set<TaskType> = [],
        now: Date = .now
    ) -> [DashboardColumn: [TransitTask]] {
        let filtered = allTasks.filter { task in
            // Exclude orphan tasks (no project)
            guard task.project != nil else { return false }

            // Project filter: non-empty set means only matching projects
            if !selectedProjectIDs.isEmpty {
                guard let projectId = task.project?.id,
                      selectedProjectIDs.contains(projectId) else { return false }
            }

            // Type filter: non-empty set means only matching types (AND with project)
            if !selectedTypes.isEmpty {
                guard selectedTypes.contains(task.type) else { return false }
            }

            return true
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
                if (lhs.status == .abandoned) != (rhs.status == .abandoned) {
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

    /// Applies a drag-drop status change via the task service.
    @MainActor
    static func applyDrop(
        task: TransitTask,
        to column: DashboardColumn,
        using service: TaskService
    ) throws {
        try service.updateStatus(task: task, to: column.primaryStatus)
    }
}
