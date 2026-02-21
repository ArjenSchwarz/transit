# Text Filter

## Overview

Add text-based search filtering to Transit tasks. On the dashboard, a native `.searchable()` search bar lets users filter the kanban board by task name or description. On the MCP side, a new `search` parameter on the `query_tasks` tool provides the same capability for agent callers. Both use case-insensitive substring matching on `name` and `taskDescription`.

## Requirements

- The dashboard MUST provide a search bar that filters visible tasks by matching against `name` and `taskDescription`
- The search MUST be case-insensitive substring matching (using `localizedCaseInsensitiveContains`)
- The search MUST combine with existing project and type filters (conjunctive AND — all active filters must match)
- The dashboard MUST show all tasks when the search text is empty (same behavior as other filters)
- The search filter state MUST be ephemeral (resets on app launch, per existing design decision)
- The `query_tasks` MCP tool MUST accept an optional `search` string parameter for text filtering
- The `query_tasks` MCP tool MUST apply the same case-insensitive substring matching on `name` and `taskDescription`
- The MCP search parameter MUST combine with all other existing filters (conjunctive AND)
- The MCP tool SHOULD trim whitespace from the search parameter; empty/whitespace-only values MUST be treated as absent
- The App Intent `QueryTasksIntent` SHOULD support a `search` field in its JSON input for parity

## Implementation Approach

**Dashboard — `.searchable()` modifier:**

Use SwiftUI's native `.searchable(text:)` modifier on the dashboard view. This gives a platform-appropriate search bar (navigation bar on iOS, toolbar on macOS) without custom UI. Pass the search text into `DashboardLogic.buildFilteredColumns()` as a new parameter.

| File | Change |
|------|--------|
| `Transit/Views/Dashboard/DashboardView.swift` | Add `@State private var searchText = ""`. Apply `.searchable(text: $searchText)`. Pass trimmed search text to `buildFilteredColumns()`. Include non-empty trimmed search text in `activeFilterCount`. |
| `Transit/Views/Dashboard/DashboardView.swift` (DashboardLogic) | Add `searchText: String = ""` parameter to `buildFilteredColumns()`. When non-empty, filter tasks where `name` or `taskDescription` contains the search text (case-insensitive). |

**MCP endpoint:**

| File | Change |
|------|--------|
| `Transit/MCP/MCPToolDefinitions.swift` | Add `"search"` property to `queryTasks` schema. Update `queryTasksDescription` to mention text search. |
| `Transit/MCP/MCPHelperTypes.swift` | Add `search: String?` to `MCPQueryFilters`. Add `search` as an explicit parameter to `from()` (matching the pattern for `type`/`projectId` — pre-parsed by caller). Update `matches()` to check substring match on `name` and `taskDescription`. |
| `Transit/MCP/MCPToolHandler.swift` | Extract `args["search"]` as trimmed optional string in `handleQueryTasks()`, pass to `MCPQueryFilters.from()`. |

**App Intent parity:**

| File | Change |
|------|--------|
| `Transit/Intents/QueryTasksIntent.swift` | Add `search: String?` to `QueryFilters`. Update `applyFilters()` to check substring match. Update the `@Parameter` description to document the new field. |

**Pattern to follow:** The type filter in `DashboardLogic.buildFilteredColumns()` (lines 179-181 of `DashboardView.swift`). Text search adds one more filter step in the same chain. For MCP, follow the pattern of `MCPQueryFilters.matches()` (lines 53-58 of `MCPHelperTypes.swift`).

**String matching approach:** Use `localizedCaseInsensitiveContains(_:)` for all text matching. This handles accented characters and locale-specific case rules correctly.

**Whitespace handling:** Both the dashboard and MCP sides MUST trim whitespace before applying the search. On the dashboard, use a computed `effectiveSearchText` property that trims `searchText`; use this for both filtering and `activeFilterCount`. On the MCP side, trim in `handleQueryTasks()` before passing to `MCPQueryFilters.from()`.

**Filter count display:** A non-empty (trimmed) search counts as 1 active filter for the badge. The filter button icon switches to filled when `activeFilterCount > 0` (existing logic, just needs search included).

**Dependencies:** SwiftUI `.searchable()` modifier (available since iOS 15), `String.localizedCaseInsensitiveContains()` (Foundation).

**Out of scope:**
- Searching metadata keys/values, project names, or comment content
- Full-text search or fuzzy matching
- Persisting search text across launches
- Search result highlighting within task cards
- Debouncing (SwiftUI handles this within `.searchable()`)
- Empty-results empty state (e.g. `ContentUnavailableView.search`) — follow-up enhancement

## Risks and Assumptions

- **Assumption:** `.searchable()` integrates cleanly with the existing `NavigationStack` in `TransitApp.swift`. The modifier should be placed on the dashboard content inside the navigation stack to get proper placement. Verified: `DashboardView` is wrapped in a `NavigationStack` at the app root.
- **Risk:** `.searchable()` placement may behave differently across iOS compact/regular and macOS layouts | **Mitigation:** The modifier attaches to the navigation bar by default, which adapts per platform. If macOS placement is awkward, a platform-specific `#if os(macOS)` adjustment can be made without changing the filter logic.
- **Assumption:** `taskDescription` is optional (`String?`) — the substring check must handle `nil` by treating it as non-matching.
- **Assumption:** In-memory filtering is acceptable for text search. The existing pattern fetches all tasks via `@Query` and filters in `buildFilteredColumns()`. For the expected task count (single-user app, hundreds of tasks at most), this is performant.
