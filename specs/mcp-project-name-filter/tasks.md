---
references:
    - specs/mcp-project-name-filter/smolspec.md
---
# MCP Project Name Filter

- [ ] 1. Add `project` parameter to `queryTasks` tool schema <!-- id:2knsk02 -->
  - Add project string property to queryTasks inputSchema in MCPToolDefinitions.swift.
  - Update the tool description to mention project name filtering.
  - Verify: build succeeds, project appears in tool schema.

- [ ] 2. Resolve project name in `handleQueryTasks` <!-- id:2knsk03 -->
  - Parse args["project"] as string, skip if empty/whitespace-only.
  - When present and projectId is absent, resolve via projectService.findProject(id: nil, name:).
  - Use resolved project UUID for MCPQueryFilters.projectId.
  - On lookup failure, return error via IntentHelpers.mapProjectLookupError().
  - When projectId is also provided, projectId takes precedence.
  - Verify: manual test with MCP client confirming filter works.
  - Blocked-by: 2knsk02 (Add `project` parameter to `queryTasks` tool schema)

- [ ] 3. Add unit tests for project name filter <!-- id:2knsk04 -->
  - Test: query with valid project name returns only tasks from that project.
  - Test: query with unknown project name returns error.
  - Test: query with both projectId and project uses projectId.
  - Test: query with empty project string returns all tasks (treated as absent).
  - Test: project filter combined with status/type filters.
  - Verify: make test-quick passes.
  - Blocked-by: 2knsk03 (Resolve project name in `handleQueryTasks`)

- [ ] 4. Verify build and lint <!-- id:2knsk05 -->
  - Run make build and make lint.
  - Fix any issues.
  - Verify: clean build on both iOS and macOS, no lint warnings.
  - Blocked-by: 2knsk04 (Add unit tests for project name filter)
