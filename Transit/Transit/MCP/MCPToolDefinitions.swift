#if os(macOS)

// MARK: - Tool Definitions

nonisolated enum MCPToolDefinitions {
    static let all: [MCPToolDefinition] = [
        createTask, updateTaskStatus, queryTasks, addComment, getProjects,
        createMilestone, queryMilestones, updateMilestone, deleteMilestone, updateTask
    ]

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
                "metadata": .object("Key-value metadata (optional, string values)"),
                "milestone": .string("Milestone name (within the task's project)"),
                "milestoneDisplayId": .integer("Milestone display ID (e.g. 3 for M-3, takes precedence over name)")
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
    private static let queryTasksDescription = "Search and filter tasks. All filters are optional — omit all to return every task. Use displayId for single-task lookup with full details. Use project for case-insensitive name filtering. status accepts an array of statuses to include. not_status accepts an array of statuses to exclude. unfinished=true excludes done and abandoned tasks (merged with not_status if both provided). Use search for case-insensitive substring matching on task name and description."

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
                "project": .string("Project name (optional, case-insensitive)"),
                "search": .string("Text search on task name and description (case-insensitive substring match)"),
                "milestone": .string("Filter by milestone name"),
                "milestoneDisplayId": .integer("Filter by milestone display ID (e.g. 3 for M-3)")
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

    // MARK: - Milestone Tools

    // swiftlint:disable:next line_length
    private static let createMilestoneDescription = "Create a new milestone within a project. At least one of 'project' or 'projectId' is required."

    static let createMilestone = MCPToolDefinition(
        name: "create_milestone",
        description: createMilestoneDescription,
        inputSchema: .object(
            properties: [
                "name": .string("Milestone name (unique within project)"),
                "project": .string("Project name (case-insensitive)"),
                "projectId": .string("Project UUID (takes precedence over name)"),
                "description": .string("Optional description")
            ],
            required: ["name"]
        )
    )

    // swiftlint:disable:next line_length
    private static let queryMilestonesDescription = "List milestones with optional filters. Returns all milestones if no filters specified."

    static let queryMilestones = MCPToolDefinition(
        name: "query_milestones",
        description: queryMilestonesDescription,
        inputSchema: .object(
            properties: [
                "displayId": .integer("Milestone display ID for single-milestone lookup (e.g. 3 for M-3)"),
                "project": .string("Filter by project name"),
                "projectId": .string("Filter by project UUID"),
                "status": .array(
                    "Filter by status(es)",
                    enumValues: MilestoneStatus.allCases.map(\.rawValue)
                ),
                "search": .string("Search milestone name and description (case-insensitive substring)")
            ],
            required: []
        )
    )

    // swiftlint:disable:next line_length
    private static let updateMilestoneDescription = "Update a milestone's name, description, or status. Identify by displayId or milestoneId."

    static let updateMilestone = MCPToolDefinition(
        name: "update_milestone",
        description: updateMilestoneDescription,
        inputSchema: .object(
            properties: [
                "displayId": .integer("Milestone display ID (e.g. 3 for M-3)"),
                "milestoneId": .string("Milestone UUID"),
                "name": .string("New name"),
                "description": .string("New description"),
                "status": .stringEnum(
                    "New status",
                    values: MilestoneStatus.allCases.map(\.rawValue)
                )
            ],
            required: []
        )
    )

    // swiftlint:disable:next line_length
    private static let deleteMilestoneDescription = "Delete a milestone. Tasks assigned to it lose their association but are not deleted. Identify by displayId or milestoneId."

    static let deleteMilestone = MCPToolDefinition(
        name: "delete_milestone",
        description: deleteMilestoneDescription,
        inputSchema: .object(
            properties: [
                "displayId": .integer("Milestone display ID (e.g. 3 for M-3)"),
                "milestoneId": .string("Milestone UUID")
            ],
            required: []
        )
    )

    // swiftlint:disable:next line_length
    private static let updateTaskDescription = "Update a task's properties. Currently supports milestone assignment. Identify task by displayId or taskId."

    static let updateTask = MCPToolDefinition(
        name: "update_task",
        description: updateTaskDescription,
        inputSchema: .object(
            properties: [
                "displayId": .integer("Task display ID (e.g. 42 for T-42)"),
                "taskId": .string("Task UUID"),
                "milestone": .string("Milestone name (within task's project). Use clearMilestone to unassign."),
                "milestoneDisplayId": .integer("Milestone display ID (e.g. 3 for M-3, takes precedence over name)"),
                "clearMilestone": .boolean("Set to true to remove milestone assignment")
            ],
            required: []
        )
    )
}

#endif
