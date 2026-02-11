import AppIntents

struct TransitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateTaskIntent(),
            phrases: [
                "Create a task in \(.applicationName)",
                "Add a task to \(.applicationName)",
                "New \(.applicationName) task"
            ],
            shortTitle: "Create Task",
            systemImageName: "plus.circle"
        )
        
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Create a new \(.applicationName) task"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.square"
        )

        AppShortcut(
            intent: UpdateStatusIntent(),
            phrases: [
                "Update task status in \(.applicationName)",
                "Move a \(.applicationName) task"
            ],
            shortTitle: "Update Status",
            systemImageName: "arrow.right.circle"
        )

        AppShortcut(
            intent: QueryTasksIntent(),
            phrases: [
                "Show tasks in \(.applicationName)",
                "Query \(.applicationName) tasks",
                "List \(.applicationName) tasks"
            ],
            shortTitle: "Query Tasks",
            systemImageName: "magnifyingglass"
        )
    }
}
