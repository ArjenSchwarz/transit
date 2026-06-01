# Search Empty State

## Overview

When the dashboard search bar has text entered but no tasks match, the board currently shows a generic "No matching tasks. Clear filters to see all tasks." overlay (shared with the project/type/milestone filters). This change adds a dedicated search empty state — SwiftUI's `ContentUnavailableView.search(text:)`, which renders "No Results for '<query>'" — for the case where text search is the *only* active filter. This was explicitly deferred from the parent text-filter feature (`specs/text-filter/smolspec.md`, line 61) and confirmed as a follow-up in PR #41 review (T-198).

## Requirements

- When tasks exist, search text is the only active filter (no project/type/milestone selected), and no task matches, the dashboard MUST show an empty state that displays "No Results" together with the current trimmed search query. (The ticket's acceptance criterion is specifically `ContentUnavailableView.search(text:)`.)
- When project, type, or milestone filters are active (with or without search text) and no tasks match, the dashboard MUST keep showing the existing generic "No matching tasks. Clear filters to see all tasks." message.
- When there are no tasks at all, the dashboard MUST show "No tasks yet. Tap + to create one." — even if search text is present (an empty database takes precedence over any query; see decision_log.md Decision 2).
- The search bar MUST remain visible when the search empty state is shown, so the user can edit or clear the query.
- The search empty state and the generic filter empty state MUST each carry a distinct accessibility identifier so automated tests can verify which state is shown.
- The empty-state selection logic — including the precedence rules above — MUST be covered by unit tests that do not render the view.

## Implementation Approach

**Files:**

| File | Change |
|------|--------|
| `Transit/Transit/Views/Dashboard/DashboardView.swift` | Add the empty-state selection logic to the `DashboardLogic` enum (defined at line 301, alongside `buildFilteredColumns`); use it from the `.overlay` (lines 82–88). |
| `Transit/TransitTests/DashboardSearchTests.swift` | Unit tests for the new selection function (matches the existing search-test suite). |
| `Transit/TransitUITests/` | UI test asserting the search empty state appears for a non-matching query and the search field stays present. |

**1. Pure selection function (testability — addresses the branch logic):**
Add to `DashboardLogic` an `EmptyStateKind` enum and a pure function that decides the state from plain inputs (no SwiftUI types):

```
enum EmptyStateKind: Equatable { case none, noTasks, search(text: String), filtered }

static func emptyStateKind(hasAnyTask: Bool, columnsAllEmpty: Bool,
                           searchText: String, hasOtherFilters: Bool) -> EmptyStateKind
```

Logic, in order (most specific first):
1. `!hasAnyTask` → `.noTasks` (empty database wins regardless of search text)
2. `!columnsAllEmpty` → `.none`
3. search text non-empty AND `!hasOtherFilters` → `.search(text:)`
4. search text non-empty OR `hasOtherFilters` → `.filtered`
5. otherwise → `.none`

This makes the branch decision verifiable by unit test rather than only by UI test.

**2. View wiring:**
- Add a `hasOtherFilters` computed property (project/type/milestone only) next to the existing `hasAnyFilter` (lines 39–44). Pass `effectiveSearchText` (already trimmed, lines 35–37) as `searchText`.
- Replace the `if/else if` in the `.overlay` (lines 82–88) with a `switch` over `DashboardLogic.emptyStateKind(...)`:
  - `.noTasks` → `EmptyStateView(message: "No tasks yet. Tap + to create one.")`
  - `.search(let text)` → `ContentUnavailableView.search(text: text)`
  - `.filtered` → `EmptyStateView(message: "No matching tasks.\nClear filters to see all tasks.")`
  - `.none` → no overlay content

**3. Accessibility identifiers (testability — addresses telling the states apart):**
Attach identifiers at the call sites in `DashboardView` (do NOT modify the shared `EmptyStateView`, which is also used by `AddTaskSheet` and `ColumnView`):
- search state → `.accessibilityIdentifier("dashboard.searchEmptyState")`
- generic filter state → `.accessibilityIdentifier("dashboard.filterEmptyState")`

Follow the existing pattern (`ReportView.swift:79` uses `.accessibilityIdentifier("report.emptyState")`; `DashboardView` already uses `dashboard.*` identifiers, e.g. line 211).

**Searchable placement:** `.searchable(text: $searchText)` (line 90) is attached to the board content, *outside* the conditional overlay, so the search bar stays visible when results are empty. This MUST NOT be moved inside the overlay branching (see "Searchable Modifier Placement" in the Swift language rules — placing it on content that gets replaced makes the search bar disappear).

**Dependencies:** `ContentUnavailableView.search(text:)` (SwiftUI, iOS 17+/macOS 14+ — well within the iOS 26 / macOS 26 target). No new dependencies.

**Out of scope:**
- Changing the filter logic, `buildFilteredColumns()`, or `matchesFilters()`.
- Changing the generic multi-filter empty-state message or the zero-tasks message text.
- A combined "search + filters" empty state distinct from the generic filter message.
- Search result highlighting, suggestions, or `.searchable` scopes.

## Risks and Assumptions

- **Assumption:** The `.overlay` covers both the `SingleColumnView` and `KanbanBoardView` branches because it is applied to the `GeometryReader` content in `body` (line 82), not to either child. Verified against current code.
- **Accepted behavior:** On iPhone portrait, the full-bleed overlay covers the segmented column switcher in `SingleColumnView` (the `Picker` at `SingleColumnView.swift:14-42`). This is pre-existing behavior (the generic empty state already does this) and is acceptable — when there are no results there is nothing to switch between. No per-layout work is added.
- **Assumption:** `ContentUnavailableView.search(text:)` renders acceptably over the `BoardBackground` glass/gradient on all three platforms. | **Mitigation:** It is the same `ContentUnavailableView` family already used elsewhere in the app; poor contrast would be a cosmetic follow-up, not a blocker.
- **Risk:** A future contributor moves `.searchable` inside the overlay branching, making the bar vanish when empty. | **Mitigation:** Documented above and asserted by the UI test (search field remains present while the empty state is shown).
- **Decision:** When search text and another filter are both active, the generic "clear filters" message wins (not the search state). Recorded in decision_log.md Decision 1.
