# MCP Task ID Filter

## Overview

The MCP server's `query_tasks` tool currently supports filtering by status, type, and projectId, but cannot look up a specific task by its display ID. This makes it impossible for MCP clients (like Claude Code) to fetch details for a single known task (e.g., T-47). Adding a `displayId` filter enables single-task lookup and brings `query_tasks` to parity with `update_task_status`, which already accepts `displayId`.

## Requirements

- The `query_tasks` MCP tool MUST accept an optional `displayId` integer parameter (e.g., `47` for T-47)
- When `displayId` is provided, the tool MUST use a predicate-based fetch (via `taskService.findByDisplayID()`) and return early, short-circuiting the full-table fetch
- When `displayId` is provided, the response MUST include `description` (string or null) and `metadata` (JSON object `[String: String]`, omitted if empty) fields for the matched task
- When `displayId` is provided alongside other filters (status, type, projectId), all filters MUST apply conjunctively (AND). The matched task is returned only if it also satisfies the other filters
- When no task matches the given `displayId`, the tool MUST return an empty array (not an error), consistent with query semantics
- The `displayId` filter MUST NOT change the response format for queries without `displayId` (existing behavior unchanged — no description/metadata fields)
- The tool description MUST be updated to mention single-task lookup capability so MCP clients can discover it

## Implementation Approach

Two files need changes:

1. **`Transit/Transit/MCP/MCPToolHandler.swift`**:
   - Add `"displayId": .integer("Task display ID (e.g. 42 for T-42)")` to the `queryTasks` tool definition input schema (line ~321)
   - Update the `queryTasks` tool description to mention displayId lookup
   - In `handleQueryTasks`, check for `displayId` argument first. If present, use `taskService.findByDisplayID()` to fetch the single task and return early before the `allTasks` fetch. Apply remaining filters (status, type, projectId) to the found task. Serialize with description and metadata included
   - Add a `detailed` parameter (Bool, default false) to `taskToDict`. When true, include `description` (from `taskDescription`) and `metadata` (from the `metadata` computed property, as a `[String: String]` JSON object, omitted when empty)

2. **`Transit/TransitTests/MCPToolHandlerTests.swift`**:
   - Add tests: displayId match found (with description/metadata in response), no match returns empty array, displayId combined with status filter

Existing patterns to follow:
- `update_task_status` (line ~157) already demonstrates `displayId` parameter parsing: `args["displayId"] as? Int`
- `taskService.findByDisplayID()` (`TaskService.swift:128`) handles lookup with predicate-based fetch
- `taskToDict` (line ~247) is the single place that serialises task responses

Dependencies: `TaskService.findByDisplayID()` (exists), `TransitTask.taskDescription` and `TransitTask.metadata` properties (exist)

Out of scope:
- Adding a dedicated `get_task` tool (query_tasks with displayId filter is sufficient)
- Changing the response format for non-displayId queries
- Adding `taskId` (UUID) filter to `query_tasks` (can be added later if needed)

## Risks and Assumptions

- **Risk**: `taskService.findByDisplayID()` throws both `taskNotFound` and `duplicateDisplayID`. **Mitigation**: Catch `taskNotFound` and return `[]`. Let `duplicateDisplayID` propagate as an error result with a descriptive message, since it indicates a data integrity problem that should not be silently hidden.
- **Assumption**: MCP clients pass `displayId` as an integer, not a string. The existing pattern in `update_task_status` uses `as? Int` which handles JSON number types correctly.
- **Assumption**: Including `description` and `metadata` only for displayId queries (not all queries) is acceptable, since these fields add payload size that's unnecessary when listing many tasks.
- **Assumption**: No input validation needed for negative or zero displayId values. `findByDisplayID` will throw `taskNotFound`, which returns `[]`. This is consistent with how `update_task_status` handles invalid IDs.
