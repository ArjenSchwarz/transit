# Implementation Explanation: get_projects MCP Tool (T-110)

## Beginner Level

### What Changed

Transit is a task tracking app that has a built-in MCP (Model Context Protocol) server so AI agents like Claude can create and manage tasks programmatically. Before this change, agents had to already know the name or UUID of a project to interact with it. There was no way to ask "what projects exist?"

This change adds a new `get_projects` command that returns a list of all projects with their details — name, ID, description, colour, and how many active tasks each has. It's like adding a "show me all projects" button for agents.

### Why It Matters

Without this, agents have to guess project names or have them hardcoded. If a project gets renamed or a new one is created, the agent breaks. This tool closes that gap by letting agents discover projects dynamically.

### Key Concepts

- **MCP (Model Context Protocol)**: A standard for AI agents to communicate with applications via JSON-RPC. Transit runs a local HTTP server that speaks MCP.
- **Tool**: An MCP operation that an agent can call — similar to a function. Transit already had `create_task`, `update_task_status`, `query_tasks`, and `add_comment`.
- **Active task count**: The number of tasks that are not in a terminal state (Done or Abandoned).

---

## Intermediate Level

### Changes Overview

Three source files modified, two spec files added:

| File | Change |
|------|--------|
| `MCPToolDefinitions.swift` | Added `getProjects` tool definition with empty input schema |
| `MCPToolHandler.swift` | Added `get_projects` case in dispatch switch + `handleGetProjects()` handler |
| `MCPToolHandlerTests.swift` | Updated tools/list count (4→5), added 3 new tests |
| `specs/get-projects-mcp/` | Smolspec and task list |
| `CHANGELOG.md` | Entry for new tool |

### Implementation Approach

The handler follows the same fetch-map-encode pattern as `handleQueryTasks`:

1. Create a `FetchDescriptor<Project>` sorted by `\Project.name`
2. Fetch all projects from `projectService.context`
3. Map each to a `[String: Any]` dictionary with the required fields
4. Conditionally include `gitRepo` only when non-nil
5. Encode via `IntentHelpers.encodeJSONArray` and return as a text result

The field mapping note is important: the SwiftData model uses `projectDescription` (because `description` conflicts with Swift's `CustomStringConvertible`), but the JSON key is `description` for API clarity.

### Trade-offs

- **No filtering/pagination**: Acceptable because Transit is single-user and project count is inherently small (tens, not thousands).
- **No App Intent counterpart**: This is MCP-only. A corresponding Shortcuts intent could be added separately but wasn't needed for the agent use case.
- **Synchronous active task count**: `ProjectService.activeTaskCount(for:)` iterates the tasks relationship. This works because the handler fetches from the same `ModelContext` that loads relationships, so lazy loading succeeds.

---

## Expert Level

### Technical Deep Dive

The implementation is minimal and correct. `handleGetProjects()` is a synchronous method (no `async`) because it only does a SwiftData fetch — no display ID allocation or CloudKit interaction needed. This is simpler than `handleCreateTask` which must be `async` for the display ID allocator.

The `FetchDescriptor` sort by `\Project.name` uses SwiftData's built-in sort which delegates to SQLite `ORDER BY` — consistent and locale-unaware (byte ordering). This matches the spec's "alphabetically by name" requirement for ASCII project names.

`activeTaskCount(for:)` counts tasks where `!status.isTerminal`. Since the projects are fetched from `projectService.context` and that same context holds the relationship graph, SwiftData's lazy loading works correctly without additional fetches. If a future refactor introduced a separate `ModelContext` for the handler, this would silently return 0 for the count (the relationship collection would be empty in the new context).

### Architecture Impact

This is an additive change with no effect on existing tools. The dispatch switch in `handleToolCall` gains one case. The tool definition is registered in the static `all` array so it automatically appears in `tools/list` responses.

The unrelated code reformatting in the same commit (collapsing switch arms in `handleCreateTask`, renaming `isoFormatter` → `fmt` in `handleAddComment`) is cosmetic and doesn't affect behaviour, though it does make the diff noisier than necessary.

### Potential Issues

- **No test for `gitRepo` conditional inclusion**: The spec requires `gitRepo` only when non-nil. The implementation handles this correctly, but no test verifies the presence or absence of this field. Low risk since the logic is a simple `if let`.
- **Dictionary key ordering in JSON**: `encodeJSONArray` uses `JSONSerialization` which doesn't guarantee key order. Tests check individual keys rather than full JSON strings, so this is fine.

---

## Completeness Assessment

### Fully Implemented

| Requirement | Evidence |
|---|---|
| Expose `get_projects` tool | `MCPToolDefinitions.getProjects` registered in `all` array |
| Include projectId, name, description, colorHex, activeTaskCount | `handleGetProjects()` maps all five fields |
| Include gitRepo only when non-nil | `if let gitRepo = project.gitRepo { dict["gitRepo"] = gitRepo }` |
| JSON array response | Returns via `IntentHelpers.encodeJSONArray` |
| Alphabetical sort by name | `SortDescriptor(\Project.name)` in `FetchDescriptor` |
| No required parameters | `inputSchema: .object(properties: [:], required: [])` |
| Appear in tools/list | Registered in `MCPToolDefinitions.all` |
| Error result on fetch failure | `catch` block returns `errorResult("Failed to fetch projects: \(error)")` |

### Test Coverage

| Test | What it verifies |
|---|---|
| `toolsListReturnsFiveTools` | Tool appears in tools/list, count is 5 |
| `getProjectsReturnsCorrectFieldsAndSortOrder` | All required fields present, alphabetical ordering, correct activeTaskCount per project |
| `getProjectsReturnsEmptyArrayWhenNoProjects` | Empty array returned with no projects |
| `getProjectsIncludesGitRepoWhenSetAndOmitsWhenNil` | `gitRepo` present with value when set, absent when nil |
| `getProjectsActiveTaskCountExcludesTerminalTasks` | Done and Abandoned tasks excluded from count |

### Not Tested (Low Risk)

- Fetch failure error path (would require mocking SwiftData internals)
