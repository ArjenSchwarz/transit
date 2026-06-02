# Implementation: Search Empty State (T-198)

Explanation of the dashboard search empty state feature at three expertise levels, followed by a completeness assessment against the smolspec requirements.

Commits: `84351fa` (implementation), `610e17b` (pre-push review fix).

---

## Beginner Level

### What Changed / What This Does

The dashboard shows tasks in columns (Idea, Planning, Spec, In Progress, Done/Abandoned). There's a search bar at the top. Before this change, if you typed something into the search bar and nothing matched, the board just went blank with a generic message: "No matching tasks. Clear filters to see all tasks."

Now, when you search and nothing matches — and search is the *only* thing you're filtering by — the board shows Apple's standard "No Results" screen with your search term in it (e.g. *No Results for "banana"*). This is the same empty-results screen you see in Mail, Settings, and other Apple apps.

If you also have other filters turned on (a project, a task type, or a milestone), the board keeps the old "Clear filters" message instead, because in that case clearing a filter — not changing your search — is more likely what you want.

### Why It Matters

It's a small polish that makes the app feel native and tells the user exactly what happened: their search found nothing. The generic message was vaguer. This was a known follow-up that was deliberately left out of the original search feature and is now done.

### Key Concepts

- **Empty state**: the screen an app shows when there's nothing to display. A good empty state explains *why* it's empty and what to do next.
- **`ContentUnavailableView.search`**: a ready-made Apple component for "your search found nothing." We didn't build the visuals; we just told the system when to show it and passed it the search text.
- **Filter**: a control that narrows down what you see. The dashboard has four: text search, project, task type, and milestone.

---

## Intermediate Level

### Changes Overview

All production code lives in one file, `Transit/Transit/Views/Dashboard/DashboardView.swift`:

1. **`DashboardLogic.EmptyStateKind`** — a small enum with four cases: `.none`, `.noTasks`, `.search(text:)`, `.filtered`. It names the four things the dashboard's overlay can show (or not show).
2. **`DashboardLogic.emptyStateKind(hasAnyTask:columnsAllEmpty:searchText:hasOtherFilters:)`** — a pure function (no SwiftUI types in or out) that maps the current board state to one `EmptyStateKind`.
3. **`DashboardEmptyStateOverlay`** — a tiny private `View` that `switch`es over the kind and renders the matching empty state, attaching accessibility identifiers.
4. **`hasOtherFilters`** — a computed property that is true when a project/type/milestone filter is active (it deliberately excludes search text, unlike the existing `hasAnyFilter`).
5. **compute-once hoist** — `filteredColumns` is now read into a single `let columns` at the top of `body` and reused, instead of being recomputed by both the board and the overlay.

Tests: six unit tests in `DashboardSearchTests.swift` exercise the pure function; two UI tests in `SearchEmptyStateUITests.swift` verify the rendered behavior.

### Implementation Approach

The key decision was to pull the "which empty state?" choice out of the view body and into a pure function. SwiftUI view bodies can only be exercised through (slow, flaky) UI tests; a pure function can be unit-tested deterministically. The view then becomes a thin `switch`.

The precedence is encoded as ordered guards (most specific first):

```
1. !hasAnyTask                        -> .noTasks       (empty database wins)
2. !columnsAllEmpty                   -> .none          (there are matches; show nothing)
3. hasSearch && !hasOtherFilters      -> .search(text:) (search is the only filter)
4. hasSearch || hasOtherFilters       -> .filtered      (generic "clear filters")
5. else                               -> .none
```

The `.searchable` modifier stays on `DashboardView.body`, *outside* the `.overlay`, so the search bar never disappears when the empty state shows — this is an explicit SwiftUI pitfall the spec called out.

Accessibility identifiers (`dashboard.searchEmptyState`, `dashboard.filterEmptyState`) are attached at the call site inside `DashboardEmptyStateOverlay`, not on the shared `EmptyStateView` (which is also used by `AddTaskSheet` and `ColumnView` and must not change).

### Trade-offs

- **Pure function vs inline `if/else`**: more code (an enum + a function) for deterministic unit-testability. Recorded as decision_log Decision 3.
- **Search-only vs always-on search state**: when search *and* another filter are both active, the generic "clear filters" message wins, because clearing the other filter is the more useful hint. Recorded as Decision 1.
- **Empty-DB precedence**: an empty database shows "No tasks yet" even if there is search text, because there is nothing to search. Recorded as Decision 2.

---

## Expert Level

### Technical Deep Dive

`emptyStateKind` is total over its input domain and side-effect-free, which is why all branch precedence (including the two non-obvious tie-breaks) is covered by fast `@Test` cases rather than XCUITest. The two UI tests are scoped to what only the UI can prove: that the `.search` identifier actually renders, that the search field survives the overlay (the `.searchable`-placement guarantee), and that a non-search filter routes to `.filtered` rather than `.search`. The board UI-test scenario seeds four tasks of types feature/research/chore/bug with `nil` descriptions, so `"ZZZNOMATCH"` and a Documentation type-filter are both guaranteed no-match inputs.

The `columnsAllEmpty` input is `filteredColumns.values.allSatisfy(\.isEmpty)`. `filteredColumns` runs `DashboardLogic.buildFilteredColumns` (an O(n) filter + group + per-column sort + 48h terminal cutoff). The review fix (`610e17b`) hoists `filteredColumns` into a single `let columns` in `body`, so it is computed once per render and shared by both the board view and the overlay — previously it was a recomputed property read in both places, doubling the work in the common no-filter case and recomputing on geometry-only changes inside the `GeometryReader`. The `let`-before-views form keeps the `@ViewBuilder` mechanics (including the `#if os(macOS)` modifier in the chain) intact.

### Architecture Impact

The empty-state decision now lives in `DashboardLogic` alongside `buildFilteredColumns`, keeping all dashboard view logic in one testable namespace. `EmptyStateKind` is a closed enum; adding a fifth empty state (e.g. a dedicated "all tasks are old/terminal" state) is a localized change: add a case, add a guard, add the render arm, add tests. The selection function takes primitive inputs, so it has no coupling to `@Query`, `ModelContext`, or SwiftUI.

### Potential Issues

- **Blank board, no message** when tasks exist, no filters are active, and every task is terminal and older than the 48-hour Done/Abandoned cutoff → `emptyStateKind` returns `.none`. This is **identical to pre-existing behavior** (the old `if/else` also showed nothing) and is explicitly out of scope for T-198. Confirmed acceptable by the author during review.
- **`ContentUnavailableView.search` over `BoardBackground`**: rendered over the glass/gradient background; if contrast were ever poor it's a cosmetic follow-up, not a correctness issue.
- **Identifier propagation**: `.accessibilityIdentifier` on the `ContentUnavailableView.search` result is matched in UI tests via `descendants(matching: .any)`; verified passing in isolation. Full `make test-ui` is deferred to the actual push (a pre-existing, unrelated `testClearAll` flake exists in the suite).

---

## Completeness Assessment

Against the six MUST requirements in `smolspec.md`:

| # | Requirement | Status | Evidence |
|---|-------------|--------|----------|
| 1 | Search-only no-match shows `ContentUnavailableView.search` with the trimmed query | ✅ Fully implemented | `.search(let text)` arm in `DashboardEmptyStateOverlay`; `emptyStateKind` case 3; unit test `emptyStateSearchOnlyNoMatchReturnsSearchWithQuery` |
| 2 | Project/type/milestone active → keep generic "No matching tasks. Clear filters" | ✅ Fully implemented | `.filtered` arm; `emptyStateKind` case 4; tests `emptyStateNonSearchFilterNoMatchReturnsFiltered`, `emptyStateSearchPlusOtherFilterNoMatchReturnsFiltered` |
| 3 | Zero tasks → "No tasks yet" even with search text | ✅ Fully implemented | First guard `!hasAnyTask -> .noTasks`; test `emptyStateNoTasksWinsEvenWithSearchText` |
| 4 | Search bar stays visible when the search empty state shows | ✅ Fully implemented | `.searchable` on `body`, outside the overlay; UI test `testSearchEmptyStateShowsAndSearchFieldPersists` asserts the search field persists |
| 5 | Distinct accessibility identifiers on search vs generic empty states | ✅ Fully implemented | `dashboard.searchEmptyState` / `dashboard.filterEmptyState`; both UI tests query them |
| 6 | Empty-state selection logic covered by unit tests that don't render the view | ✅ Fully implemented | Pure `emptyStateKind`; six `@Test` cases in `DashboardSearchTests` calling it with value inputs |

**Fully implemented:** all six requirements.
**Partially implemented:** none.
**Missing:** none.

**Decision-log adherence:** Decision 1 (search+filter → generic), Decision 2 (empty-DB precedence), and Decision 3 (pure function) are all honored in code and individually unit-tested.

**Validation note:** every requirement was explainable end-to-end at all three levels with a direct line to code and a test, so none is flagged as potentially incomplete. The one behavior that is *not* covered (blank board when all tasks are old terminal tasks) is intentionally out of scope and matches prior behavior, not a gap introduced by this change.
