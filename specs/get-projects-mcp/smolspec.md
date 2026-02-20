# Get Projects MCP Command

## Overview

Add a `get_projects` tool to the Transit MCP server so agents can discover available projects without guessing names. Currently agents must know a project name or UUID to create tasks or filter queries — this tool closes that gap by listing all projects with their metadata.

## Requirements

- The MCP server MUST expose a `get_projects` tool that returns all projects
- Each project in the response MUST include: `projectId` (UUID string), `name`, `description`, `colorHex`, `activeTaskCount` (number of non-terminal tasks)
- Each project MUST include `gitRepo` only when non-nil
- The response MUST be a JSON array of project objects
- Projects MUST be sorted alphabetically by name
- The tool MUST accept no required parameters
- The tool MUST appear in the `tools/list` response
- On fetch failure, the tool MUST return an error result with a descriptive message

## Implementation Approach

**Files to modify:**
- `Transit/Transit/MCP/MCPToolDefinitions.swift` — add `getProjects` tool definition to `all` array
- `Transit/Transit/MCP/MCPToolHandler.swift` — add `get_projects` case to tool dispatch switch and a `handleGetProjects` handler method
- `Transit/TransitTests/MCPToolHandlerTests.swift` — add tests for the new tool; update existing `toolsListReturnsFourTools` test (now expects 5 tools)

**Pattern to follow:**
The existing `handleQueryTasks` handler in `MCPToolHandler.swift:190-241` demonstrates the fetch-map-encode pattern: fetch via `FetchDescriptor`, map to dictionaries, return via `IntentHelpers.encodeJSONArray`. The new handler is simpler — no filters, no task resolution.

**Project data access:**
`ProjectService` already has `context: ModelContext` exposed publicly and an `activeTaskCount(for:)` method. Use `FetchDescriptor<Project>()` with `SortDescriptor(\Project.name)` for consistent ordering (same approach used in `ProjectEntityQuery.suggestedEntities()`).

**Field mapping note:** The `Project` model stores the description as `projectDescription` (not `description`). The response JSON key MUST be `description` for clarity to API consumers.

**Out of scope:**
- No corresponding App Intent (can be added separately if needed)
- No filtering parameters (project count is small enough to return all)
- No pagination

## Risks and Assumptions

- **Assumption:** Project count is small enough that returning all projects in a single response is acceptable. Transit is a single-user app, so this is safe.
- **Risk:** `activeTaskCount(for:)` iterates the optional `tasks` relationship via lazy-loading. This works because the handler fetches projects from `projectService.context` — the same `ModelContext` that loads the relationship. **Mitigation:** If a future refactor introduces a separate context, this will need revisiting. For now, the single-context design is correct.
