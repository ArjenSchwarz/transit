---
references:
    - specs/search-empty-state/smolspec.md
---
# Search Empty State

- [x] 1. Empty-state selection logic chooses the correct state for every filter combination <!-- id:2q7l19f -->
  - Add a pure function to the DashboardLogic enum (DashboardView.swift) plus an EmptyStateKind value type with four cases: none, no-tasks, search(text), filtered.
  - Inputs: whether any task exists, whether all columns are empty, the trimmed search text, and whether non-search (project/type/milestone) filters are active.
  - Precedence: empty database first (returns no-tasks even with search text), then search-only no-match (returns search carrying the query), then generic filter (returns filtered); otherwise none.
  - Success: function and EmptyStateKind compile; logic matches the precedence in smolspec.md.
  - References: specs/search-empty-state/smolspec.md

- [x] 2. Unit tests verify empty-state selection precedence across all cases <!-- id:2q7l19g -->
  - Add Swift Testing unit tests in DashboardSearchTests.swift covering: no tasks present returns no-tasks even with search text; search-only with no match returns search carrying the query text; search-only with matches returns none; a non-search filter active with no match returns filtered; search plus another filter with no match returns filtered (not search); whitespace-only or empty search is treated as no search.
  - Success: tests pass via make test-quick.
  - Blocked-by: 2q7l19f (Empty-state selection logic chooses the correct state for every filter combination)
  - References: specs/search-empty-state/smolspec.md

- [x] 3. Dashboard shows the search empty state and keeps the search bar visible <!-- id:2q7l19h -->
  - Replace the if/else in the dashboard .overlay (DashboardView.swift:82-88) with a switch over the selection function. Search-only no-match renders ContentUnavailableView.search(text:) with the trimmed query; the generic filter case keeps the existing 'No matching tasks' message; the zero-tasks case is unchanged.
  - Attach distinct accessibility identifiers at the call sites (dashboard.searchEmptyState and dashboard.filterEmptyState) without modifying the shared EmptyStateView. Add a hasOtherFilters computed property (project/type/milestone only).
  - Keep .searchable attached outside the overlay so the search bar stays visible when the empty state shows.
  - Success: builds via make build; lint clean via make lint.
  - Blocked-by: 2q7l19f (Empty-state selection logic chooses the correct state for every filter combination)
  - References: specs/search-empty-state/smolspec.md

- [x] 4. UI test confirms search empty state appears and search field persists <!-- id:2q7l19i -->
  - Add a UI test using the board scenario: type a query matching no task, assert the dashboard.searchEmptyState element appears and the search field is still present; and that activating a non-search filter with no match shows dashboard.filterEmptyState instead of the search state.
  - Success: passes via make test-ui.
  - Blocked-by: 2q7l19h (Dashboard shows the search empty state and keeps the search bar visible)
  - References: specs/search-empty-state/smolspec.md
