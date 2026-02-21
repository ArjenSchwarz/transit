# Implementation Explanation: Text Filter (T-180)

## Beginner Level

### What Changed
Transit now has a search bar on the kanban dashboard. When you type text into it, only tasks whose name or description contain that text remain visible. The same search capability is available to AI agents through the MCP tool and App Intent interfaces.

### Why It Matters
Before this change, users could only filter tasks by project and type. If you had dozens of tasks and wanted to find one by name, you had to scan visually. Now you can type a few characters and the board narrows down instantly.

### Key Concepts
- **`.searchable()` modifier**: A built-in SwiftUI feature that adds a platform-native search bar — it appears in the navigation bar on iOS and the toolbar on macOS, without any custom UI code.
- **Case-insensitive substring matching**: Searching for "login" matches "Fix Login Bug", "LOGIN issue", etc. Uses `localizedCaseInsensitiveContains` which also handles accented characters correctly across locales.
- **Conjunctive filtering (AND)**: Search combines with project and type filters. If you select project "Alpha" and search "bug", only tasks in project Alpha with "bug" in their name or description appear.
- **Ephemeral state**: The search text resets when you relaunch the app — it's not saved anywhere.

---

## Intermediate Level

### Changes Overview
6 source files modified, 2 new test files added (16 tests total):

| Layer | File | Change |
|-------|------|--------|
| Dashboard | `DashboardView.swift` | `@State searchText`, `effectiveSearchText` computed property, `.searchable()` modifier, `activeFilterCount` updated |
| Dashboard Logic | `DashboardView.swift` (DashboardLogic) | New `searchText` parameter on `buildFilteredColumns()`, extracted `matchesFilters()` private method |
| MCP Schema | `MCPToolDefinitions.swift` | `search` property added to `queryTasks` tool schema |
| MCP Filters | `MCPHelperTypes.swift` | `search: String?` on `MCPQueryFilters`, matching logic in `matches()` |
| MCP Handler | `MCPToolHandler.swift` | Extract and trim `search` from args, pass to `MCPQueryFilters.from()` |
| App Intent | `QueryTasksIntent.swift` | `search: String?` on `QueryFilters`, matching in `applyFilters()`, updated parameter description |

### Implementation Approach
The implementation follows the existing filter pattern exactly. Each layer already had project and type filters; text search is added as one more AND-combined filter step in the same chain.

**Dashboard path**: `DashboardView` holds `@State searchText`, computes `effectiveSearchText` (trimmed), passes it to `DashboardLogic.buildFilteredColumns()`. The logic was refactored to extract `matchesFilters()` as a private static method, keeping the closure in `buildFilteredColumns()` clean. The `activeFilterCount` now includes `+1` when `effectiveSearchText` is non-empty, which makes the filter button badge and accessibility value reflect active search.

**MCP path**: `handleQueryTasks()` extracts the raw search string, trims whitespace, and converts empty/whitespace-only to `nil` before passing to `MCPQueryFilters.from()`. The `matches()` method checks `name` and `taskDescription` with `localizedCaseInsensitiveContains`.

**App Intent path**: `QueryFilters` (private `Codable` struct) gets a `search: String?` property. `applyFilters()` trims whitespace and applies the same substring matching in its single-pass filter loop.

### Trade-offs
- **In-memory filtering** rather than SwiftData predicates: The app already fetches all tasks via `@Query` and filters in memory. For a single-user app with at most hundreds of tasks, this is fine. A predicate-based approach would be premature optimisation and would complicate the code.
- **No debouncing**: SwiftUI's `.searchable()` handles interaction throttling internally — no manual debounce needed.
- **Double-trimming on dashboard path**: `effectiveSearchText` trims whitespace, and `buildFilteredColumns()` trims again internally. This is deliberate — `buildFilteredColumns` is a public static method that can be called directly (e.g., from tests), so it defensively trims its own input.

---

## Expert Level

### Technical Deep Dive
The filter logic is replicated across three layers (dashboard, MCP, App Intent) rather than shared through a common function. This is intentional — each layer operates on different data types and in different contexts:
- Dashboard: operates on in-memory `TransitTask` objects from `@Query`
- MCP: operates on `TransitTask` objects from `FetchDescriptor` fetch, through `MCPQueryFilters`
- App Intent: operates on `TransitTask` objects through its own `QueryFilters` Codable struct

Sharing a single filter function would require either a protocol abstraction (over-engineering for three identical 4-line checks) or coupling the layers together.

The `localizedCaseInsensitiveContains` choice is correct for a user-facing search — it handles Unicode normalization and locale-specific case folding. This is slower than a simple `lowercased().contains()` but the performance difference is negligible at the expected scale.

### Architecture Impact
No new types, no new protocols, no structural changes. The feature adds one parameter to three existing filter paths. The `DashboardLogic` refactoring (extracting `matchesFilters()`) improves readability but doesn't change the public API — the `buildFilteredColumns()` signature just gains an optional parameter with a default value.

### Potential Issues
- **`.searchable()` placement**: Attached directly to the dashboard view body, after `.navigationTitle()`. This relies on the `NavigationStack` being at the app root (`TransitApp.swift`). If the navigation structure changes, the search bar placement could break.
- **No empty-state for search**: When search returns no results, the dashboard shows empty columns but no "No results for X" message. The smolspec explicitly defers this as a follow-up enhancement.
- **MCP `search` with `displayId`**: When both `search` and `displayId` are provided, the single-task lookup runs first, then `filters.matches(task)` applies the search filter. This is correct but somewhat non-obvious — a search that doesn't match the looked-up task returns an empty array.

---

## Completeness Assessment

### Fully Implemented
- Dashboard search bar via `.searchable()` with case-insensitive substring matching on name and description
- Search combines conjunctively with project and type filters
- Active filter count includes search text
- Ephemeral search state (resets on launch via `@State`)
- MCP `query_tasks` `search` parameter with whitespace trimming
- App Intent `QueryTasksIntent` `search` field with same matching
- 7 dashboard search unit tests + 9 MCP search integration tests

### Requirement Traceability

| Requirement | Status | Evidence |
|---|---|---|
| Dashboard search bar filters by name and description | Done | `DashboardView.swift:75` (`.searchable`), `DashboardView.swift:235-238` (matching) |
| Case-insensitive substring matching | Done | `localizedCaseInsensitiveContains` used in all three layers |
| Combines with project and type filters (AND) | Done | `matchesFilters()` checks all three sequentially |
| Empty search shows all tasks | Done | `searchText.isEmpty` guard skips filter |
| Ephemeral search state | Done | `@State private var searchText = ""` resets per view lifecycle |
| MCP `search` parameter | Done | `MCPToolDefinitions.swift:72`, `MCPHelperTypes.swift:11` |
| MCP case-insensitive matching | Done | `MCPHelperTypes.swift:59-63` |
| MCP combines with other filters (AND) | Done | `matches()` checks all filters sequentially |
| MCP trims whitespace, empty treated as absent | Done | `MCPToolHandler.swift:207`, nil coalescing on empty |
| App Intent `search` field | Done | `QueryTasksIntent.swift:28`, `QueryTasksIntent.swift:194-197` |

### Not Implemented (Explicitly Out of Scope)
- Searching metadata, project names, or comments
- Full-text search or fuzzy matching
- Persisting search across launches
- Search result highlighting in cards
- Empty-results empty state (`ContentUnavailableView.search`)
