---
references:
    - specs/mcp-task-id-filter/smolspec.md
---
# MCP Task ID Filter

## Implementation

- [x] 1. Add displayId parameter to query_tasks tool schema and update tool description
  - The query_tasks tool definition in MCPToolDefinitions accepts a displayId integer parameter. The tool description communicates that displayId can be used for single-task lookup.
  - Verify: build succeeds, tools/list response includes displayId in query_tasks schema.

- [x] 2. displayId lookup returns matching task with description and metadata
  - When query_tasks receives a displayId argument, it uses taskService.findByDisplayID() to fetch the task and returns early before the full-table fetch.
  - The response includes description and metadata fields. taskToDict accepts a detailed parameter that controls inclusion of these fields.
  - Catch taskNotFound and return empty array; let duplicateDisplayID propagate as error.
  - Verify: calling query_tasks with displayId of an existing task returns a single-element array with name, description, metadata, and all standard fields.

- [x] 3. displayId filter composes with other filters
  - When displayId is provided alongside status, type, or projectId filters, all filters apply conjunctively.
  - The matched task is only returned if it also satisfies the other filters.
  - Verify: query_tasks with displayId and a non-matching status filter returns empty array.

## Testing

- [x] 4. Test displayId lookup returns task with detail fields
  - Unit test: create a task with description and metadata, query by displayId, verify response contains description and metadata fields alongside standard fields.
  - Verify: test passes with make test-quick.

- [x] 5. Test displayId not found returns empty array
  - Unit test: query by a displayId that does not exist, verify response is an empty JSON array (not an error).
  - Verify: test passes with make test-quick.

- [x] 6. Test displayId with non-matching status filter returns empty
  - Unit test: create a task in idea status, query with its displayId plus status=done, verify empty array returned.
  - Verify: test passes with make test-quick.

- [x] 7. Verify existing query_tasks tests still pass
  - Run the full MCPToolHandlerTests suite to confirm no regressions in existing query behavior.
  - Covers: queryAllTasks, queryTasksFilterByStatus, queryTasksFilterByType, queryTasksReturnsProjectInfo.
  - Verify: make test-quick passes with all existing and new tests green.
