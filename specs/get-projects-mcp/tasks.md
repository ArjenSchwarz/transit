---
references:
    - specs/get-projects-mcp/smolspec.md
---
# Get Projects MCP Command

- [x] 1. Add `getProjects` tool definition <!-- id:9yxyrpn -->
  - Add a `getProjects` static property to `MCPToolDefinitions` in `MCPToolDefinitions.swift` and register it in the `all` array. No required parameters. Follow the existing tool definition pattern.

- [x] 2. Implement `handleGetProjects` handler <!-- id:9yxyrpo -->
  - Add `get_projects` case to the tool dispatch switch in `handleToolCall` and a `handleGetProjects` method in `MCPToolHandler.swift`.
  - Fetch all projects via `FetchDescriptor<Project>()` sorted by name.
  - Map each project to a dict with: projectId, name, description (from `projectDescription`), colorHex, activeTaskCount, and gitRepo (only when non-nil).
  - Return error result on fetch failure.
  - Blocked-by: 9yxyrpn (Add `getProjects` tool definition)

- [x] 3. Update tools/list test for 5 tools <!-- id:9yxyrpp -->
  - Rename `toolsListReturnsFourTools` to `toolsListReturnsFiveTools`, update the count assertion to 5, and verify `get_projects` is in the returned tool names.
  - Blocked-by: 9yxyrpn (Add `getProjects` tool definition)

- [x] 4. Test: projects returned with correct fields and sort order <!-- id:9yxyrpq -->
  - Create two projects (e.g. Bravo and Alpha), add tasks to them, then call `get_projects`.
  - Verify each project has projectId, name, description, colorHex, and activeTaskCount.
  - Verify alphabetical ordering (Alpha before Bravo).
  - Blocked-by: 9yxyrpo (Implement `handleGetProjects` handler)

- [x] 5. Test: empty array when no projects exist <!-- id:9yxyrpr -->
  - Call `get_projects` with no projects in the context. Verify the response is an empty JSON array.
  - Blocked-by: 9yxyrpo (Implement `handleGetProjects` handler)

- [x] 6. Test: activeTaskCount excludes terminal tasks <!-- id:9yxyrps -->
  - Create a project with tasks in mixed statuses including done and abandoned.
  - Verify activeTaskCount only counts non-terminal tasks.
  - Blocked-by: 9yxyrpo (Implement `handleGetProjects` handler)

- [x] 7. Verify tests and lint pass <!-- id:9yxyrpt -->
  - Run `make test-quick` and `make lint` to confirm everything passes.
  - Blocked-by: 9yxyrpp (Update tools/list test for 5 tools), 9yxyrpq (Test: projects returned with correct fields and sort order), 9yxyrpr (Test: empty array when no projects exist), 9yxyrps (Test: activeTaskCount excludes terminal tasks)
