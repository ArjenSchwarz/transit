import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \TransitTask.lastStatusChangeDate, order: .reverse) private var allTasks: [TransitTask]
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var selectedTypes: Set<TaskType> = []
    @State private var selectedMilestones: Set<UUID> = []
    @State private var sortOrder: DashboardLogic.ColumnSortOrder = .recent
    @State private var selectedColumn: DashboardColumn = .inProgress // [req 13.3]
    @State private var selectedTask: TransitTask?
    @State private var showAddTask = false
    @State private var searchText = ""
    @Environment(TaskService.self) private var taskService
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.resolvedTheme) private var resolvedTheme

    /// Minimum width (in points) for a single kanban column.
    private static let columnMinWidth: CGFloat = 200

    private var isPhoneLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var effectiveSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasAnyFilter: Bool {
        !selectedProjectIDs.isEmpty
            || !selectedTypes.isEmpty
            || !selectedMilestones.isEmpty
            || !effectiveSearchText.isEmpty
    }

    private var filteredColumns: [DashboardColumn: [TransitTask]] {
        DashboardLogic.buildFilteredColumns(
            allTasks: allTasks,
            selectedProjectIDs: selectedProjectIDs,
            selectedTypes: selectedTypes,
            selectedMilestones: selectedMilestones,
            searchText: effectiveSearchText,
            sortOrder: sortOrder
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
            } else if hasAnyFilter && filteredColumns.values.allSatisfy(\.isEmpty) {
                EmptyStateView(message: "No matching tasks.\nClear filters to see all tasks.")
            }
        }
        .navigationTitle("Transit")
        .searchable(text: $searchText)
        .toolbarTitleDisplayMode(.inline)
        #if os(macOS)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ProjectFilterMenu(
                    projects: projects,
                    selectedProjectIDs: $selectedProjectIDs
                )
                TypeFilterMenu(selectedTypes: $selectedTypes)
                MilestoneFilterMenu(
                    projects: projects,
                    selectedProjectIDs: selectedProjectIDs,
                    selectedMilestones: $selectedMilestones
                )
                sortOrderButton
                clearAllButton
            }
            ToolbarSpacer(.fixed)
            ToolbarItemGroup(placement: .primaryAction) {
                addButton
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
        .onChange(of: selectedProjectIDs) { _, _ in
            selectedMilestones.removeAll()
        }
    }

    // MARK: - Toolbar Buttons

    @ViewBuilder
    private var clearAllButton: some View {
        if hasAnyFilter {
            Button {
                selectedProjectIDs.removeAll()
                selectedTypes.removeAll()
                selectedMilestones.removeAll()
                searchText = ""
            } label: {
                Label("Clear All", systemImage: "xmark.circle.fill")
            }
            .accessibilityIdentifier("dashboard.clearAllFilters")
            .accessibilityLabel("Clear all filters")
        }
    }

    private var sortOrderButton: some View {
        Button {
            sortOrder = sortOrder == .recent ? .organized : .recent
        } label: {
            Label(
                sortOrder == .recent ? "Recent" : "Organized",
                systemImage: sortOrder == .recent ? "clock" : "list.bullet"
            )
        }
        .accessibilityIdentifier("dashboard.sortOrder")
        .accessibilityLabel("Sort order: \(sortOrder == .recent ? "Recent" : "Organized")")
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

    enum ColumnSortOrder {
        case recent
        case organized
    }

    /// Testable column builder: groups tasks by column, applies project, type, milestone,
    /// and text search filters, 48-hour cutoff for terminal tasks, and sorting rules.
    static func buildFilteredColumns(
        allTasks: [TransitTask],
        selectedProjectIDs: Set<UUID>,
        selectedTypes: Set<TaskType> = [],
        selectedMilestones: Set<UUID> = [],
        searchText: String = "",
        sortOrder: ColumnSortOrder = .recent,
        now: Date = .now
    ) -> [DashboardColumn: [TransitTask]] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered = allTasks.filter { task in
            matchesFilters(
                task: task,
                selectedProjectIDs: selectedProjectIDs,
                selectedTypes: selectedTypes,
                selectedMilestones: selectedMilestones,
                searchText: trimmedSearch
            )
        }

        var grouped = Dictionary(grouping: filtered) { $0.status.column }

        // Ensure all columns exist (even if empty)
        for column in DashboardColumn.allCases where grouped[column] == nil {
            grouped[column] = []
        }

        return grouped.mapValues { tasks in
            tasks.filter { task in
                if task.status.isTerminal {
                    // Defensive: nil completionDate treated as just-completed [req 5.6]
                    return task.completionDate?.isWithin48Hours(of: now) ?? true
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

                switch sortOrder {
                case .recent:
                    return lhs.lastStatusChangeDate > rhs.lastStatusChangeDate
                case .organized:
                    return compareOrganized(lhs, rhs)
                }
            }
        }
    }

    private static func compareOrganized(_ lhs: TransitTask, _ rhs: TransitTask) -> Bool {
        let lhsProject = lhs.project?.name ?? ""
        let rhsProject = rhs.project?.name ?? ""
        let projectComparison = lhsProject.localizedCaseInsensitiveCompare(rhsProject)
        if projectComparison != .orderedSame { return projectComparison == .orderedAscending }

        let allCases = TaskType.allCases
        let lhsTypeIndex = allCases.firstIndex(of: lhs.type) ?? allCases.count
        let rhsTypeIndex = allCases.firstIndex(of: rhs.type) ?? allCases.count
        if lhsTypeIndex != rhsTypeIndex { return lhsTypeIndex < rhsTypeIndex }

        switch (lhs.permanentDisplayId, rhs.permanentDisplayId) {
        case let (lhsId?, rhsId?) where lhsId != rhsId: return lhsId < rhsId
        case (nil, .some): return false
        case (.some, nil): return true
        default: break
        }

        return lhs.lastStatusChangeDate > rhs.lastStatusChangeDate
    }

    private static func matchesFilters(
        task: TransitTask,
        selectedProjectIDs: Set<UUID>,
        selectedTypes: Set<TaskType>,
        selectedMilestones: Set<UUID>,
        searchText: String
    ) -> Bool {
        guard task.project != nil else { return false }

        if !selectedProjectIDs.isEmpty {
            guard let projectId = task.project?.id,
                  selectedProjectIDs.contains(projectId) else { return false }
        }

        if !selectedTypes.isEmpty {
            guard selectedTypes.contains(task.type) else { return false }
        }

        // In-memory milestone filter (can't use #Predicate for optional relationships)
        if !selectedMilestones.isEmpty {
            guard let milestoneId = task.milestone?.id,
                  selectedMilestones.contains(milestoneId) else { return false }
        }

        if !searchText.isEmpty {
            let nameMatch = task.name.localizedCaseInsensitiveContains(searchText)
            let descMatch = task.taskDescription?.localizedCaseInsensitiveContains(searchText) ?? false
            let displayIdMatch = task.displayID.formatted.localizedCaseInsensitiveContains(searchText)
            guard nameMatch || descMatch || displayIdMatch else { return false }
        }

        return true
    }

    /// Whether a drag-drop onto `column` should actually change the task's status.
    /// Returns `false` when the task is already in the target column, preventing
    /// same-column drops from mutating status or timestamps. [T-192]
    static func shouldApplyDrop(task: TransitTask, to column: DashboardColumn) -> Bool {
        task.status.column != column
    }

    /// Applies a drag-drop status change via the task service.
    /// No-op when the task is already in the target column — this prevents
    /// abandoned tasks from flipping to done and avoids resetting timestamps
    /// on same-column drops. [T-192]
    @MainActor
    static func applyDrop(
        task: TransitTask,
        to column: DashboardColumn,
        using service: TaskService
    ) throws {
        guard shouldApplyDrop(task: task, to: column) else { return }
        try service.updateStatus(task: task, to: column.primaryStatus)
    }
}
