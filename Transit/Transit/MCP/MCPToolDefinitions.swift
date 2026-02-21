#if os(macOS)

// MARK: - Tool Definitions

nonisolated enum MCPToolDefinitions {
    static let all: [MCPToolDefinition] = [createTask, updateTaskStatus, queryTasks, addComment, getProjects]

    static let createTask = MCPToolDefinition(
        name: "create_task",
        description: "Create a new task in Transit. The task starts in Idea status.",
        inputSchema: .object(
            properties: [
                "name": .string("Task name (required)"),
                "type": .stringEnum(
                    "Task type (required)",
                    values: TaskType.allCases.map(\.rawValue)
                ),
                "projectId": .string("Project UUID (optional, precedence over name)"),
                "project": .string("Project name (optional, case-insensitive)"),
                "description": .string("Task description (optional)"),
                "metadata": .object("Key-value metadata (optional, string values)")
            ],
            required: ["name", "type"]
        )
    )

    // swiftlint:disable:next line_length
    private static let updateTaskStatusDescription = "Move a task to a different status. Identify the task by displayId (e.g. 42 for T-42) or taskId (UUID)."

    static let updateTaskStatus = MCPToolDefinition(
        name: "update_task_status",
        description: updateTaskStatusDescription,
        inputSchema: .object(
            properties: [
                "displayId": .integer("Task display ID (e.g. 42 for T-42)"),
                "taskId": .string("Task UUID"),
                "status": .stringEnum(
                    "Target status (required)",
                    values: TaskStatus.allCases.map(\.rawValue)
                ),
                "comment": .string("Optional comment to add with status change"),
                "authorName": .string("Author name (required when comment is provided)")
            ],
            required: ["status"]
        )
    )

    // swiftlint:disable:next line_length
    private static let queryTasksDescription = "Search and filter tasks. All filters are optional — omit all to return every task. Use displayId for single-task lookup with full details. Use project for case-insensitive name filtering. status accepts an array of statuses to include. not_status accepts an array of statuses to exclude. unfinished=true excludes done and abandoned tasks (merged with not_status if both provided)."

    static let queryTasks = MCPToolDefinition(
        name: "query_tasks",
        description: queryTasksDescription,
        inputSchema: .object(
            properties: [
                "displayId": .integer("Task display ID for single-task lookup (e.g. 42 for T-42)"),
                "status": .array(
                    "Filter by status (include tasks matching any listed status)",
                    enumValues: TaskStatus.allCases.map(\.rawValue)
                ),
                "not_status": .array(
                    "Exclude tasks matching any listed status",
                    enumValues: TaskStatus.allCases.map(\.rawValue)
                ),
                "unfinished": .boolean("When true, exclude done and abandoned tasks"),
                "type": .stringEnum(
                    "Filter by type",
                    values: TaskType.allCases.map(\.rawValue)
                ),
                "projectId": .string("Filter by project UUID"),
                "project": .string("Project name (optional, case-insensitive)")
            ],
            required: []
        )
    )

    private static let addCommentDescription = "Add a comment to a task. Identify the task by displayId or taskId."

    static let addComment = MCPToolDefinition(
        name: "add_comment",
        description: addCommentDescription,
        inputSchema: .object(
            properties: [
                "displayId": .integer("Task display ID (e.g. 42 for T-42)"),
                "taskId": .string("Task UUID"),
                "content": .string("Comment text (required)"),
                "authorName": .string("Author name (required)")
            ],
            required: ["content", "authorName"]
        )
    )
    static let getProjects = MCPToolDefinition(
        name: "get_projects",
        description: "List all projects with metadata. Returns an array of project objects sorted by name.",
        inputSchema: .object(properties: [:], required: [])
    )
}

#endif
