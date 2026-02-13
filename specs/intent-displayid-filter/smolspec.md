# Intent DisplayId Filter

## Overview

Add `displayId` support to the `QueryTasksIntent` App Intent so CLI callers and Shortcuts can look up a single task by its human-facing ID (e.g. T-42). When `displayId` is provided, the intent returns a detailed single-task response including description and metadata — matching the existing MCP `query_tasks` tool behaviour.

## Requirements

- The system MUST accept an optional `displayId` integer field in the JSON input to `QueryTasksIntent`
- The system MUST return detailed task output (description, metadata) when `displayId` is provided
- The system MUST return an empty array `[]` when no task matches the given `displayId` (not an error)
- The system MUST apply all filters (status, type, projectId, date filters) alongside `displayId` when both are present
- The system SHOULD use a direct `FetchDescriptor` lookup by `permanentDisplayId` rather than filtering the full task list
- The system MUST update the `@Parameter` description to document the `displayId` field

## Implementation Approach

**Files to modify:**
- `Transit/Transit/Intents/QueryTasksIntent.swift` — add `displayId` to `QueryFilters`, add early-return lookup path in `execute()`, extend `taskToDict` with `detailed` flag
- `Transit/TransitTests/QueryTasksIntentTests.swift` — add test cases for displayId lookup, not-found, and combined filters

**Pattern reference:**
The MCP `query_tasks` handler (`Transit/Transit/MCP/MCPToolHandler.swift:194-244`) implements the same feature for the MCP interface. The approach follows the same overall pattern but differs in one detail: the MCP handler delegates to `TaskService.findByDisplayID()`, whereas this intent uses `FetchDescriptor` directly on `modelContext` — because `QueryTasksIntent` does not have a `TaskService` dependency and adding one would change the `execute()` signature and all existing tests. This is a read-only lookup, so skipping `TaskService` is fine.

**Steps:**

1. Add `displayId: Int?` to the private `QueryFilters` Codable struct
2. In `execute()`, check for `displayId` early. If present, fetch via `FetchDescriptor` with `#Predicate { $0.permanentDisplayId == displayId }` on the `modelContext` parameter
3. Wrap the found task in an array and pass through the existing `applyFilters()` — this applies all filters (status, type, projectId, date) uniformly with zero new filter logic
4. If `applyFilters` returns an empty array (task not found or excluded by filters), return `[]`
5. If task passes filters, return detailed output using `taskToDict` with a `detailed: true` flag that includes `description` and `metadata`
6. Update the `@Parameter` description to include: `"displayId" (integer, e.g. 42 for T-42) for single-task lookup with detailed output (description, metadata).`

**Existing code to reuse:**
- `QueryTasksIntent.taskToDict()` (line 195) — extend with `detailed: Bool = false` parameter that adds `description` and `metadata` fields when true (matching `MCPToolHandler.taskToDict` at line 266). The existing call site at line 110 continues to work via the default value.
- `QueryTasksIntent.applyFilters()` (line 151) — call with `[task]` array for the single-task path. All existing filter logic (including date filters) applies automatically.

**Out of scope:**
- No separate "Get Task" App Intent — the displayId filter on QueryTasksIntent covers this use case
- No changes to the MCP handler (already implemented)

## Risks and Assumptions

- **Assumption:** `permanentDisplayId` is always an `Int?` on `TransitTask` and can be queried via `#Predicate` — confirmed by existing `TaskService.findByDisplayID()` implementation
- **Risk:** Adding `displayId` to the Codable `QueryFilters` struct could reject previously valid JSON that happens to include a `displayId` field with a non-integer value | **Mitigation:** This is the desired behaviour — invalid types should fail JSON decoding as with all other fields
- **Assumption:** Non-positive `displayId` values (0, -1) simply return `[]` — no validation needed since no tasks have non-positive display IDs
