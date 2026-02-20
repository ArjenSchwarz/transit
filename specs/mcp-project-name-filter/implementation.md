# Implementation Explanation: MCP Project Name Filter (T-179)

## Beginner Level

### What Changed
The Transit MCP server's `query_tasks` tool now accepts a `project` parameter — a project name string — in addition to the existing `projectId` (UUID). This lets MCP clients filter tasks by human-readable project names without first looking up the UUID via `get_projects`.

### Why It Matters
Before this change, an MCP client (like Claude Code) that wanted to query tasks for a specific project had to make two calls: one to `get_projects` to find the UUID, then `query_tasks` with that UUID. Now it can do it in one call using the name directly — the same way `create_task` already worked.

### Key Concepts
- **MCP (Model Context Protocol)**: A protocol that lets AI agents communicate with Transit's task management features. Transit runs an HTTP server on macOS that agents can call.
- **Project name resolution**: Converting a human-readable name like "Transit" into the internal UUID that the database uses. This involves case-insensitive matching (so "transit" and "TRANSIT" both find the same project).
- **Precedence**: When both `projectId` and `project` are provided, `projectId` wins. This prevents ambiguity and matches how `create_task` already behaves.

---

## Intermediate Level

### Changes Overview

Three source files changed, one test file added:

| File | Change |
|------|--------|
| `MCPToolDefinitions.swift` | Added `project` property to `queryTasks` input schema; updated tool description |
| `MCPToolHandler.swift` | Added project name resolution in `handleQueryTasks` before filter construction |
| `MCPQueryProjectNameTests.swift` | 8 tests covering all spec requirements |
| `CHANGELOG.md` | Three entries documenting the feature, tests, and spec |

### Implementation Approach

The implementation reuses the existing `ProjectService.findProject(id:name:)` method — the same one `handleCreateTask` uses. The resolution happens early in `handleQueryTasks`, before `MCPQueryFilters` is constructed:

1. If `projectId` is present, parse it as UUID (existing behavior, takes precedence)
2. Else if `project` is a non-empty, non-whitespace string, resolve via `findProject(id: nil, name:)`
3. On resolution failure (not found or ambiguous), return an error via `IntentHelpers.mapProjectLookupError()`
4. The resolved UUID feeds into `MCPQueryFilters.projectId`, which the rest of the method already uses

This means the `displayId` single-task lookup path also benefits from project filtering — it's conjunctive (AND) with all other filters.

### Trade-offs

- **Error on unknown project vs empty array**: The spec chose to return an error for non-existent project names, distinguishing "no tasks in this project" from "project doesn't exist". This matches `create_task` behavior but differs from `displayId` lookup (which returns `[]` on miss).
- **No changes to `MCPQueryFilters`**: Name resolution happens before filter construction, keeping the filter struct unchanged. This is simpler than adding name-based filtering to the struct itself.
- **Minor unrelated cleanup**: `stringMetadata` helper was refactored from a manual loop to `reduce(into:)` in the same commit.

---

## Expert Level

### Technical Deep Dive

The core change is 6 lines in `handleQueryTasks` (lines 199-204). The `else if` placement after the `projectId` check naturally implements precedence — if `projectId` is present, the `project` branch never executes.

The whitespace handling uses `trimmingCharacters(in: .whitespacesAndNewlines)` at the MCP handler level, while `ProjectService.findProject` additionally trims with `.whitespaces`. Both are needed: the handler check prevents empty-after-trim strings from triggering a lookup, and the service does its own normalization for consistency with other callers.

Error mapping uses `IntentHelpers.mapProjectLookupError()`, which returns an `IntentError` with a `.hint` string. This produces structured error messages like `"No project named \"Foo\""` or `"2 projects match \"Alpha\""`.

### Architecture Impact

This is a leaf change — no new types, no protocol changes, no structural modifications. It extends an existing tool's parameters using existing service methods. The MCP tool definition schema now matches `create_task` in having both `projectId` and `project`, establishing a consistent pattern for any future tools that need project scoping.

### Potential Issues

- **Performance**: Each `query_tasks` call with a `project` name triggers a full project fetch + in-memory filter. With small project counts (typical for a single-user app), this is negligible. Same cost as `create_task` already incurs.
- **Ambiguous names**: Case-variant duplicates (e.g., "Alpha" and "alpha") can exist from CloudKit sync. These return an error rather than silently picking one, which is the correct behavior but may surprise callers.
- **No partial matching**: Only exact case-insensitive matches work. Callers must know the exact project name. `get_projects` remains the discovery mechanism for project names.

---

## Completeness Assessment

### Fully Implemented
- All 7 smolspec requirements are covered by implementation and tests
- `project` parameter in tool schema with correct description
- Case-insensitive name resolution via existing `ProjectService.findProject`
- `projectId` precedence when both provided
- Error on unknown and ambiguous project names
- Empty/whitespace-only strings treated as absent
- Conjunctive composition with `status`, `type`, and `displayId` filters
- Tool description updated to mention the `project` parameter

### Partially Implemented
- None

### Missing
- None — all spec requirements are addressed
