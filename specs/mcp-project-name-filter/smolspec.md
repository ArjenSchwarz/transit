# MCP Project Name Filter

## Overview

The MCP server's `query_tasks` tool accepts `projectId` (UUID) for filtering by project, but not `project` (name). This is inconsistent with `create_task`, which accepts both. Adding a `project` name parameter enables MCP clients to filter tasks by project without needing to look up the UUID first via `get_projects`.

## Requirements

- The `query_tasks` MCP tool MUST accept an optional `project` string parameter for case-insensitive project name filtering
- When both `projectId` and `project` are provided, `projectId` MUST take precedence (consistent with `create_task` behavior)
- When a `project` name matches zero projects, the tool MUST return an error result with a descriptive message (consistent with `create_task` behavior)
- When a `project` name matches multiple projects, the tool MUST return an error result with a descriptive message (consistent with `create_task` behavior)
- When `project` is an empty or whitespace-only string, the tool MUST treat it as absent (no project filter applied)
- The `project` filter MUST compose with other filters (`status`, `type`, `displayId`) conjunctively (AND)
- The tool description MUST be updated to mention the `project` parameter

## Implementation Approach

Reuse the existing `ProjectService.findProject(id:name:)` method, which already handles case-insensitive matching, whitespace trimming, and ambiguity detection. This is the same pattern used by `create_task` in `handleCreateTask`.

**Files to modify:**

1. **`Transit/Transit/MCP/MCPToolDefinitions.swift`** (~line 51-69): Add `"project": .string("Project name (optional, case-insensitive)")` to the `queryTasks` input schema properties, matching the parameter definition in `createTask`.

2. **`Transit/Transit/MCP/MCPToolHandler.swift`** (~line 192-224): In `handleQueryTasks`, parse `args["project"]` as a non-empty trimmed string. If present (and `projectId` is not), resolve it to a `Project` via `projectService.findProject(id: nil, name: projectName)` and use its UUID for the existing `projectId` filter in `MCPQueryFilters`. On lookup failure, return an error result using `IntentHelpers.mapProjectLookupError()`. This resolution happens before `MCPQueryFilters` construction, so the `displayId` code path also correctly filters by project (conjunctive AND).

3. **`Transit/TransitTests/MCPToolHandlerTests.swift`**: Add tests for project name filter — match found, no match returns error, ambiguous name returns error, combined with other filters.

**Existing patterns to follow:**
- `handleCreateTask` (line ~106-149) demonstrates `project` name parsing and `projectService.findProject()` usage
- `IntentHelpers.mapProjectLookupError()` maps `ProjectLookupError` to structured error responses
- `MCPQueryFilters.projectId` already handles the actual filtering once resolved

**Dependencies:** `ProjectService.findProject(id:name:)` (exists), `IntentHelpers.mapProjectLookupError()` (exists)

**Out of scope:**
- Adding project name filter to other tools (e.g., `update_task_status`)
- Partial/fuzzy name matching (exact case-insensitive match only, consistent with `create_task`)
- Changing `MCPQueryFilters` struct (name resolution happens before filter construction)

## Risks and Assumptions

- **Risk**: Project name resolution adds a fetch to every `query_tasks` call that uses the `project` parameter. **Mitigation**: Project count is small (fetches all projects, filters in memory). This is the same approach `create_task` already uses without issues.
- **Assumption**: Returning an error (not an empty array) for unknown project names is the correct behavior, since it distinguishes "no tasks in this project" from "project doesn't exist". This differs from `displayId` lookup (which returns `[]` on miss) because project names are a prerequisite filter, not a task identifier.
- **Assumption**: The `projectId` takes precedence behavior is consistent with `create_task` and doesn't need to be configurable.
