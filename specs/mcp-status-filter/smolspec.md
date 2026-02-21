# MCP Status Filter Improvements

## Overview

The MCP server's `query_tasks` tool accepts a single `status` string for filtering, which limits callers to exact single-status matches. This change adds multi-status inclusion (`status` as array), status exclusion (`not_status` as array), and an `unfinished` boolean shorthand that excludes done/abandoned tasks. These are the most common filtering patterns used by MCP clients.

## Requirements

- The `query_tasks` tool MUST accept `status` as either a string (single value) or an array of strings (multiple values) for backward compatibility
- The `query_tasks` tool MUST accept an optional `not_status` array parameter that excludes tasks matching any of the listed statuses
- The `query_tasks` tool MUST accept an optional `unfinished` boolean parameter; when `true`, it MUST exclude tasks with status `done` or `abandoned`
- When `unfinished` is `true` and `not_status` is also provided, the exclusion sets MUST be merged (union)
- When both `status` and `not_status` are provided, a task MUST match at least one `status` value AND match none of the `not_status` values (conjunctive AND)
- Empty arrays (`status: []`, `not_status: []`) MUST be treated as absent (no filter applied), same as omitting the parameter
- No validation of logical consistency across parameters — contradictory combinations (e.g., `status: ["done"], unfinished: true`) silently return empty results
- The MCP tool schema MUST describe `status` as an array type with enum items, `not_status` as an array type with enum items, and `unfinished` as a boolean
- The tool description MUST document the new parameters and their interaction

## Implementation Approach

Extend `JSONSchemaProperty` with `.boolean()` and `.array()` schema factories, update the `query_tasks` tool definition to use them, expand `MCPQueryFilters` to handle the new filter shapes, and update the handler's argument parsing.

**Files to modify:**

1. **`Transit/Transit/MCP/MCPTypes.swift`** (`JSONSchemaProperty`, ~line 149-173): Add a `.boolean()` static factory. Add an `.array()` factory that supports `items` with enum constraints. Since `JSONSchemaProperty` is a struct and cannot have a recursive stored property of its own type, define a separate `JSONSchemaItems` struct (with `type: String?` and `enumValues: [String]?`) for the items sub-schema. Add an optional `items: JSONSchemaItems?` property to `JSONSchemaProperty` and update `CodingKeys`. The enum values go on the `items` sub-schema (not on the array property itself) per JSON Schema spec.

2. **`Transit/Transit/MCP/MCPToolDefinitions.swift`** (`queryTasks`, ~line 51-70): Replace `status` with `.array()` type using string enum items. Add `not_status` as `.array()` with same enum items. Add `unfinished` as `.boolean()`. Update `queryTasksDescription` to mention the new parameters.

3. **`Transit/Transit/MCP/MCPHelperTypes.swift`** (`MCPQueryFilters`, ~line 6-17): Change `status: String?` to `statuses: [String]?`. Add `notStatuses: [String]?`. Update `matches()`: if `statuses` is set, task must be in the list; if `notStatuses` is set, task must NOT be in the list.

4. **`Transit/Transit/MCP/MCPToolHandler.swift`** (`handleQueryTasks`, ~line 207-211): Parse `status` accepting both `String` and `[String]` (wrap single string in array). Parse `not_status` as `[String]`. Parse `unfinished` as `Bool`; when `true`, merge `["done", "abandoned"]` into the not-statuses set. Construct `MCPQueryFilters` with the resolved arrays.

5. **`Transit/TransitTests/MCPStatusFilterTests.swift`** (new file): Test multi-status inclusion, status exclusion, unfinished flag, combined filters, backward-compatible single string, and edge cases (contradictory filters, empty arrays).

**Existing patterns to follow:**
- `MCPQueryProjectNameTests.swift` — test structure, `MCPTestHelpers` usage
- `handleCreateTask` project resolution — pattern for parsing optional parameters with fallback
- `JSONSchemaProperty.stringEnum()` — pattern for schema property factories

**Dependencies:** `MCPTestHelpers` (exists), `TaskService.updateStatus()` (exists for setting up test states)

**Out of scope:**
- Validating that status values in `status`/`not_status` are valid enum members (current behavior: invalid values silently match nothing)
- Adding multi-value support for the `type` filter (same pattern, separate change)
- Adding array/boolean schema support beyond what `query_tasks` needs (keep factories minimal)
- Changing the App Intents `QueryTasksIntent` (separate concern)

## Risks and Assumptions

- **Risk**: Changing `JSONSchemaProperty` to support `items` adds a new encoding path. **Mitigation**: The struct is simple and the `items` property is optional — existing factories set it to `nil` and encoding skips it.
- **Risk**: The schema changes `status` from `type: "string"` to `type: "array"`, which is a breaking schema change. **Mitigation**: MCP clients re-fetch `tools/list` on each session, so they'll see the new schema immediately. The handler accepts both string and array for runtime backward compatibility.
- **Assumption**: Backward compatibility for `status` as a single string is worth the minor parsing complexity. MCP clients may have cached the old schema or pass a string by convention.
- **Assumption**: Merging `unfinished` with explicit `not_status` (union) is more intuitive than having `not_status` override `unfinished`. Contradictory combinations (e.g., `status: ["done"], unfinished: true`) return empty results, which is correct behavior.
- **Assumption**: `not_status` naming follows the existing underscore convention (`task_status`, `not_status`) and is clearer than alternatives like `excludeStatus` which would be inconsistent with the parameter naming style.
