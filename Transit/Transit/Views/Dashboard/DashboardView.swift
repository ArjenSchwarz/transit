//
//  DashboardView.swift
//  Transit
//
//  Root dashboard view with adaptive layout switching.
//

import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \TransitTask.lastStatusChangeDate, order: .reverse) private var allTasks: [TransitTask]
    @Environment(TaskService.self) private var taskService
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var selectedColumn: DashboardColumn = .inProgress
    @State private var selectedTask: TransitTask?
    @State private var showAddTask = false
    @State private var showFilter = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private static let columnMinWidth: CGFloat = 200

    private var isPhoneLandscape: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let rawColumnCount = max(1, Int(geometry.size.width / Self.columnMinWidth))
                let columnCount = isPhoneLandscape ? min(rawColumnCount, 3) : rawColumnCount

                if columnCount == 1 {
                    SingleColumnView(
                        columns: filteredColumns,
                        selectedColumn: $selectedColumn,
                        onTaskTap: { task in
                            selectedTask = task
                        },
                        onDrop: handleDrop
                    )
                } else {
                    KanbanBoardView(
                        columns: filteredColumns,
                        onTaskTap: { task in
                            selectedTask = task
                        },
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
                    Button {
                        showFilter.toggle()
                    } label: {
                        Label(
                            selectedProjectIDs.isEmpty ? "Filter" : "\(selectedProjectIDs.count)",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    }
                    .popover(isPresented: $showFilter) {
                        FilterPopoverView(selectedProjectIDs: $selectedProjectIDs)
                    }

                    Button {
                        showAddTask = true
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        Text("Settings")
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showAddTask) {
                AddTaskSheet()
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
            }
        }
    }

    private var filteredColumns: [DashboardColumn: [TransitTask]] {
        let filtered: [TransitTask]
        if selectedProjectIDs.isEmpty {
            filtered = allTasks.filter { $0.project != nil }
        } else {
            filtered = allTasks.filter { task in
                guard let projectId = task.project?.id else { return false }
                return selectedProjectIDs.contains(projectId)
            }
        }

        let now = Date.now
        let cutoff = now.addingTimeInterval(-48 * 60 * 60)

        return Dictionary(grouping: filtered) { $0.status.column }
            .mapValues { tasks in
                tasks.filter { task in
                    if task.status.isTerminal {
                        return (task.completionDate ?? now) > cutoff
                    }
                    return true
                }
                .sorted { first, second in
                    if (first.status == .abandoned) != (second.status == .abandoned) {
                        return second.status == .abandoned
                    }
                    if first.status.isHandoff != second.status.isHandoff {
                        return first.status.isHandoff
                    }
                    return first.lastStatusChangeDate > second.lastStatusChangeDate
                }
            }
    }

    private func handleDrop(_ taskId: UUID, _ targetColumn: DashboardColumn) -> Bool {
        guard let task = allTasks.first(where: { $0.id == taskId }) else {
            return false
        }

        let targetStatus: TaskStatus
        if targetColumn == .doneAbandoned {
            targetStatus = .done
        } else {
            targetStatus = targetColumn.primaryStatus
        }

        do {
            try taskService.updateStatus(task: task, to: targetStatus)
            return true
        } catch {
            return false
        }
    }
}
