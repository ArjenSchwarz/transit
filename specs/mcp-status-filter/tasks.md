---
references:
    - specs/mcp-status-filter/smolspec.md
---
# MCP Status Filter Improvements

## Schema and Filter Infrastructure

- [x] 1. JSONSchemaProperty supports boolean and array types <!-- id:o3z0o8w -->
  - JSONSchemaItems struct exists with type and enumValues
  - JSONSchemaProperty has items: JSONSchemaItems? property
  - .boolean() and .array() static factories produce correct JSON Schema output
  - Existing schema factories still encode correctly with items as nil
  - Verified: build succeeds, existing MCP tool definitions unchanged

- [x] 2. MCPQueryFilters handles multi-status inclusion and exclusion <!-- id:o3z0o8x -->
  - MCPQueryFilters accepts statuses: [String]? and notStatuses: [String]? instead of status: String?
  - matches() returns true when task status is in statuses list (or statuses is nil/empty)
  - matches() returns false when task status is in notStatuses list
  - Both conditions compose conjunctively with existing type and projectId filters
  - Verified: unit tests cover inclusion-only, exclusion-only, combined, and nil/empty arrays
  - Blocked-by: o3z0o8w (JSONSchemaProperty supports boolean and array types)

## Handler Integration and Tool Schema

- [ ] 3. Handler parses new status filter parameters <!-- id:o3z0o8y -->
  - handleQueryTasks extracts status accepting both String and [String]
  - Extracts not_status as [String] and unfinished as Bool
  - When unfinished is true, merges [done, abandoned] into not-statuses
  - Empty arrays treated as absent (no filter)
  - Verified: unit tests cover backward compat, array input, unfinished flag, merge, empty arrays
  - Blocked-by: o3z0o8x (MCPQueryFilters handles multi-status inclusion and exclusion)

- [ ] 4. query_tasks tool schema and description updated <!-- id:o3z0o8z -->
  - status uses .array() with string enum items for all TaskStatus raw values
  - not_status uses .array() with same enum items
  - unfinished uses .boolean()
  - queryTasksDescription mentions the new parameters
  - Verified: build succeeds, tools/list response includes updated schema
  - Blocked-by: o3z0o8w (JSONSchemaProperty supports boolean and array types)

- [ ] 5. Integration tests for combined filter scenarios <!-- id:o3z0o90 -->
  - Multi-status with project filter returns correct subset
  - Exclusion filter with type filter composes correctly
  - Unfinished flag with displayId lookup still works
  - Contradictory filters return empty results
  - Backward-compatible single string status works with other filters
  - Verified: all tests pass with make test-quick
  - Blocked-by: o3z0o8y (Handler parses new status filter parameters), o3z0o8z (query_tasks tool schema and description updated)
