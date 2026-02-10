import SwiftData
import SwiftUI

struct DashboardView: View {
    private static let columnMinWidth: CGFloat = 260

    @Environment(TaskService.self) private var taskService
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @Query(sort: [SortDescriptor(\TransitTask.lastStatusChangeDate, order: .reverse)])
    private var allTasks: [TransitTask]

    @Query(sort: [SortDescriptor(\Project.name)])
    private var allProjects: [Project]

    @State private var selectedColumn: DashboardColumn = .inProgress
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var isFilterPopoverPresented = false

    private var isPhoneLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var filteredColumns: [DashboardColumn: [TransitTask]] {
        DashboardLogic.filteredColumns(
            tasks: allTasks,
            selectedProjectIDs: selectedProjectIDs,
            now: .now
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let rawColumnCount = max(1, Int(geometry.size.width / Self.columnMinWidth))
            let columnCount = isPhoneLandscape ? min(rawColumnCount, 3) : rawColumnCount

            Group {
                if columnCount == 1 {
                    SingleColumnView(
                        columns: filteredColumns,
                        selectedColumn: $selectedColumn,
                        onDropTask: handleDroppedTask
                    )
                } else {
                    KanbanBoardView(
                        columns: filteredColumns,
                        visibleCount: min(columnCount, DashboardColumn.allCases.count),
                        initialScrollTarget: isPhoneLandscape ? .planning : nil,
                        onDropTask: handleDroppedTask
                    )
                }
            }
            .overlay {
                if allTasks.isEmpty {
                    EmptyStateView(message: "No tasks yet. Tap + to create one.")
                        .padding(20)
                }
            }
        }
        .navigationTitle("Transit")
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .topBarTrailing) {
                filterButton
                addButton
                settingsButton
            }
            #else
            ToolbarItemGroup(placement: .automatic) {
                filterButton
                addButton
                settingsButton
            }
            #endif
        }
    }

    @ViewBuilder
    private var filterButton: some View {
        Button {
            isFilterPopoverPresented.toggle()
        } label: {
            if selectedProjectIDs.isEmpty {
                Image(systemName: "line.3.horizontal.decrease.circle")
            } else {
                Label("\(selectedProjectIDs.count)", systemImage: "line.3.horizontal.decrease.circle.fill")
            }
        }
        .popover(isPresented: $isFilterPopoverPresented, arrowEdge: .top) {
            FilterPopoverView(
                projects: allProjects,
                selectedProjectIDs: $selectedProjectIDs
            )
        }
    }

    @ViewBuilder
    private var addButton: some View {
        Button {
        } label: {
            Image(systemName: "plus")
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        Button {
        } label: {
            Image(systemName: "gearshape")
        }
    }

    private func handleDroppedTask(taskID: UUID, column: DashboardColumn) -> Bool {
        guard let task = allTasks.first(where: { $0.id == taskID }) else {
            return false
        }

        do {
            try DashboardLogic.applyDrop(
                task: task,
                to: column,
                using: taskService,
                now: .now
            )
            return true
        } catch {
            return false
        }
    }
}

enum DashboardLogic {
    static func filteredColumns(
        tasks: [TransitTask],
        selectedProjectIDs: Set<UUID>,
        now: Date
    ) -> [DashboardColumn: [TransitTask]] {
        var buckets = [DashboardColumn: [TransitTask]](minimumCapacity: DashboardColumn.allCases.count)
        for column in DashboardColumn.allCases {
            buckets[column] = []
        }

        let hasProjectFilter = !selectedProjectIDs.isEmpty

        for task in tasks {
            guard let projectID = task.project?.id else {
                continue
            }
            if hasProjectFilter && !selectedProjectIDs.contains(projectID) {
                continue
            }
            if task.status.isTerminal,
               !(task.completionDate ?? now).isWithinLast48Hours(referenceDate: now) {
                continue
            }

            buckets[task.status.column, default: []].append(task)
        }

        for column in DashboardColumn.allCases {
            guard var columnTasks = buckets[column] else {
                continue
            }

            columnTasks.sort { left, right in
                DashboardSort.byDashboardOrder(left, right)
            }
            buckets[column] = columnTasks
        }

        return buckets
    }

    @MainActor
    static func applyDrop(
        task: TransitTask,
        to column: DashboardColumn,
        using service: TaskService,
        now: Date
    ) throws {
        try service.updateStatus(task: task, to: column.primaryStatus, now: now)
    }
}

enum DashboardSort {
    static func byDashboardOrder(_ lhs: TransitTask, _ rhs: TransitTask) -> Bool {
        let lhsAbandoned = lhs.status == .abandoned
        let rhsAbandoned = rhs.status == .abandoned
        if lhsAbandoned != rhsAbandoned {
            return !lhsAbandoned
        }

        if lhs.status.isHandoff != rhs.status.isHandoff {
            return lhs.status.isHandoff
        }

        return lhs.lastStatusChangeDate > rhs.lastStatusChangeDate
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
}
