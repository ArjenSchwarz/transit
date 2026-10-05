#if os(macOS)
import Foundation

// MARK: - Tool Definitions
nonisolated enum MCPToolDefinitions {
    static let coreTools: [MCPToolDefinition] = [
        createTask, updateTaskStatus, queryTasks, addComment, getProjects, createProject,
        createMilestone, queryMilestones, updateMilestone, deleteMilestone, updateTask,
        MCPPortfolioToolDefinitions.queryProjectSummaries, MCPBatchToolDefinition.definition
    ]

    static let maintenanceTools: [MCPToolDefinition] = [
        scanDuplicateDisplayIds, reassignDuplicateDisplayIds
    ]

    /// Backwards-compatible alias for legacy callers — returns core tools only.
    /// Maintenance tools are gated; use `tools(includingMaintenance:)` to
    /// include them based on the runtime toggle.
    static let all: [MCPToolDefinition] = coreTools

    static func tools(includingMaintenance: Bool) -> [MCPToolDefinition] {
        includingMaintenance ? coreTools + maintenanceTools : coreTools
    }

    static func modernTools(includingMaintenance: Bool) throws -> [MCPModernToolDescriptor] {
        try tools(includingMaintenance: includingMaintenance).map { definition in
            let input: MCPJSONDocument
            let result: MCPResultSchemaDescriptor
            if definition.name == "mutate_tasks" {
                input = try MCPBatchTaskSchema.inputSchema()
                result = try MCPBatchTaskOutputSchema.descriptor(description: definition.description)
            } else {
                input = try MCPJSONDocument.parse(JSONEncoder().encode(definition.inputSchema))
                result = try MCPResultSchemas.descriptor(tool: definition.name, description: definition.description)
            }
            return MCPModernToolDescriptor(name: definition.name, description: definition.description,
                inputSchema: input, resultSchema: result)
        }
    }

    /// Names of tools gated behind `MCPSettings.maintenanceToolsEnabled`,
    /// derived from `maintenanceTools` so adding a tool there is a single edit.
    static let maintenanceToolNames: Set<String> = Set(maintenanceTools.map(\.name))

}

extension MCPToolDefinitions {
    // MARK: - Maintenance Tools

    nonisolated private static let scanDuplicateDisplayIdsDescription = """
        Scan tasks and milestones for duplicate permanentDisplayId values. Returns groups of duplicates \
        (winner + losers) without modifying any data. Read-only.
        """

    nonisolated static let scanDuplicateDisplayIds = MCPToolDefinition(
        name: "scan_duplicate_display_ids",
        description: scanDuplicateDisplayIdsDescription,
        inputSchema: .object(properties: [:], required: [])
    )

    nonisolated private static let reassignDuplicateDisplayIdsDescription = """
        Reassign fresh permanentDisplayId values to losers in each duplicate group. Advances the CloudKit \
        counter past the highest observed ID before allocation. Best-effort per group; returns per-group \
        outcomes.
        """

    nonisolated static let reassignDuplicateDisplayIds = MCPToolDefinition(
        name: "reassign_duplicate_display_ids",
        description: reassignDuplicateDisplayIdsDescription,
        inputSchema: .object(properties: [:], required: [])
    )

    nonisolated private static let createTaskDescription = """
        Create a new task in Transit. The task starts in Idea status. \
        At least one of 'project' or 'projectId' is required to identify the task's project.
        """

    nonisolated static let createTask = protected(
        MCPToolDefinition(
            name: "create_task",
            description: createTaskDescription,
            inputSchema: .object(
                properties: [
                    "name": .string("Task name (required)"),
                    "type": .stringEnum(
                        "Task type (required)",
                        values: TaskType.allCases.map(\.rawValue)
                    ),
                    "priority": .stringEnum(
                        "Task priority (optional, defaults to medium)",
                        values: TaskPriority.allCases.map(\.rawValue)
                    ),
                    "projectId": .string(
                        "Project UUID. At least one of projectId or project is required; projectId takes precedence."
                    ),
                    "project": .string(
                        "Project name (case-insensitive). At least one of projectId or project is required."
                    ),
                    "description": .string("Task description (optional)"),
                    "metadata": .object("Key-value metadata (optional, string values)"),
                    "milestone": .string("Milestone name (within the task's project)"),
                    "milestoneDisplayId": .integer(
                        "Milestone display ID (e.g. 3 for M-3, takes precedence over name)")
                ],
                required: ["name", "type"]
            )
        ))

    nonisolated private static let updateTaskStatusDescription = """
        Move a task to a different status. Identify the task by displayId (e.g. 42 for T-42) or taskId \
        (UUID).
        """

    nonisolated static let updateTaskStatus = protected(
        MCPToolDefinition(
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
        ))

    nonisolated private static let queryTasksDescription = """
    Query tasks with required detailLevel (summary/full), includeComments (boolean), and limit (1–100).
    Filters are optional; displayId accepts the same filters. Choose at most one selector: displayId,
    taskIds or displayIds (batches of 1–100 identifiers, no filters). Returns {results,nextCursor,expiresAt}.
    Lists sort by task UUID; batch outcomes retain input order/index, requested identity, and task or error
    (TASK_NOT_FOUND/AMBIGUOUS_TASK_ID). Full detail includes nullable description, nonempty metadata and
    a revision covering complete comment state. Full reads fetch comments even when includeComments=false;
    that option omits only their payload. Summary reads with includeComments=false do not fetch comments.
    A new ordinary query creates a new capture. Continue with cursor and optionally the identical retained readPolicy;
    frozen cursor replay never captures or refreshes again. Results expire five minutes after the original capture;
    replay does not extend expiry. There is no automatic retry.
    Whole-query errors are {error:{code,message}}: INVALID_INPUT, AMBIGUOUS_TASK_ID, AMBIGUOUS_FILTER,
    QUERY_FAILED, INVALID_CURSOR (start a new query), QUERY_EXPIRED, QUERY_UNAVAILABLE, or
    QUERY_CAPACITY_EXCEEDED (reduce scope/comments or retry after expiry). Unknown fields are rejected.
    status/not_status/priority accept arrays; unfinished excludes done/abandoned; search matches name/description.
    """

    nonisolated private static let queryTaskProperties: [String: JSONSchemaProperty] = [
                "detailLevel": .stringEnum("Required task detail", values: ["summary", "full"]),
                "includeComments": .boolean("Required: include comment payload; full revisions always read comments"),
                "limit": .integer("Required page size, 1 through 100"),
                "taskIds": .array("Batch of 1 through 100 UUIDs; no filters or other selectors"),
                "displayIds": .array(
                    "Batch of 1 through 100 integer IDs; no filters or other selectors", itemType: "integer"
                ),
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
                "priority": .array(
                    "Filter by priority (include tasks matching any listed priority)",
                    enumValues: TaskPriority.allCases.map(\.rawValue)
                ),
                "projectId": .string("Filter by project UUID"),
                "project": .string("Project name (optional, case-insensitive)"),
                "search": .string("Text search on task name and description (case-insensitive substring match)"),
                "milestone": .string("Filter by milestone name"),
                "milestoneDisplayId": .integer("Filter by milestone display ID (e.g. 3 for M-3)")
            ]

    nonisolated static let queryTasks = MCPToolDefinition(
        name: "query_tasks",
        description: queryTasksDescription + "\n\n" + TaskLinkQuerySchema.guidance + "\n\n" + readExecutionDescription
            + "\n\n" + MCPPortfolioToolDefinitions.snapshotTaskQueryDescription,
        inputSchema: JSONSchema(type: "object", properties: nil, required: nil, oneOf: [
            JSONSchema(type: "object",
                       properties: queryTaskProperties.merging(TaskLinkQuerySchema.properties) { _, new in new },
                       required: ["detailLevel", "includeComments", "limit"], additionalProperties: false),
            MCPPortfolioToolDefinitions.reusableContinuationSchema,
            MCPPortfolioToolDefinitions.snapshotTaskQueryInitialSchema
        ])
    )

    nonisolated private static let addCommentDescription = """
        Add a comment to a task. Identify the task by displayId or taskId.
        """

    nonisolated static let addComment = protected(
        MCPToolDefinition(
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
        ))

    nonisolated static let createProject = protected(
        MCPToolDefinition(
            name: "create_project",
            description: "Create a project. Returns projectId and metadata for subsequent task creation.",
            inputSchema: .object(
                properties: [
                    "name": .string("Project name (required; trimmed, non-empty, case-insensitively unique)"),
                    "colorHex": .string(
                        "Project color (required; six hexadecimal digits, optionally prefixed by #)"),
                    "description": .string("Project description (optional, defaults to an empty string)"),
                    "gitRepo": .string("Git repository URL or path (optional, free-form)")
                ],
                required: ["name", "colorHex"]
            )
        ))

    nonisolated static let getProjects = MCPToolDefinition(
        name: "get_projects",
        description: "List all projects with metadata. Returns an array of project objects sorted by name."
            + "\n\n" + readExecutionDescription,
        inputSchema: .object(properties: [:], required: [])
    )

    // MARK: - Milestone Tools

    nonisolated private static let createMilestoneDescription = """
        Create a new milestone within a project. At least one of 'project' or 'projectId' is required.
        """

    nonisolated static let createMilestone = protected(
        MCPToolDefinition(
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
        ))

    nonisolated private static let queryMilestonesDescription = """
        List milestones with optional filters. Returns all milestones if no filters specified.
        """

    nonisolated static let queryMilestones = MCPToolDefinition(
        name: "query_milestones",
        description: queryMilestonesDescription + "\n\n" + readExecutionDescription,
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

    nonisolated private static let updateMilestoneDescription = """
        Update a milestone's name, description, or status. Identify by displayId or milestoneId.
        """

    nonisolated static let updateMilestone = protected(
        MCPToolDefinition(
            name: "update_milestone",
            description: updateMilestoneDescription,
            inputSchema: .object(
                properties: [
                    "displayId": .integer("Milestone display ID (e.g. 3 for M-3)"),
                    "milestoneId": .string("Milestone UUID"),
                    "name": .string("New name"),
                    "description": .string(
                        "New description. Pass \"\" or whitespace-only to clear."
                    ),
                    "status": .stringEnum(
                        "New status",
                        values: MilestoneStatus.allCases.map(\.rawValue)
                    )
                ],
                required: []
            )
        ))

    nonisolated private static let deleteMilestoneDescription = """
        Delete a milestone. Tasks assigned to it lose their association but are not deleted. Identify by \
        displayId or milestoneId.
        """

    nonisolated static let deleteMilestone = protected(
        MCPToolDefinition(
            name: "delete_milestone",
            description: deleteMilestoneDescription,
            inputSchema: .object(
                properties: [
                    "displayId": .integer("Milestone display ID (e.g. 3 for M-3)"),
                    "milestoneId": .string("Milestone UUID")
                ],
                required: []
            )
        ))

    nonisolated private static let updateTaskDescription = """
        Update a task's mutable fields (name, description, type, metadata, milestone) in a single atomic \
        call. Identify task by displayId or taskId.
        """

    nonisolated static let updateTask = protected(
        MCPToolDefinition(
            name: "update_task",
            description: updateTaskDescription,
            inputSchema: .object(
                properties: [
                    "displayId": .integer("Task display ID (e.g. 42 for T-42)"),
                    "taskId": .string("Task UUID"),
                    "name": .string("New task name (trimmed; must be non-empty after trim)"),
                    "description": .string(
                        "New task description. Pass \"\" or whitespace-only to clear."
                    ),
                    "type": .stringEnum(
                        "New task type (exact lowercase match required)",
                        values: TaskType.allCases.map(\.rawValue)
                    ),
                    "priority": .stringEnum(
                        "New task priority (exact lowercase match required; omit to leave unchanged)",
                        values: TaskPriority.allCases.map(\.rawValue)
                    ),
                    "metadata": .object(
                        "Replaces all metadata. Pass {} to clear it. Values must be strings."
                    ),
                    "milestone": .string("Milestone name (within task's project). Use clearMilestone to unassign."),
                    "milestoneDisplayId": .integer(
                        "Milestone display ID (e.g. 3 for M-3, takes precedence over name)"),
                    "clearMilestone": .boolean("Set to true to remove milestone assignment")
                ],
                required: []
            )
        ))
}

#endif
