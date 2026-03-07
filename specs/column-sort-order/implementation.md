# Column Sort Order - Implementation Explanation

## Beginner Level

### What Changed
Transit's kanban dashboard shows tasks organized in columns (Idea, Planning, Spec, In Progress, Done/Abandoned). Previously, tasks within each column were always sorted by when they last changed status — most recent first. This change adds a second way to sort: "Organized" mode, which groups tasks by project name, then by task type (bug, feature, chore, etc.), then by their ID number.

A toggle button in the toolbar lets the user switch between "Recent" (the original sort) and "Organized" (the new sort). The button shows a clock icon when in Recent mode and a list icon when in Organized mode. The sort choice resets to Recent every time the app launches — it's not saved.

### Why It Matters
When you have many tasks across multiple projects, the date-based sort can feel chaotic — tasks from different projects are interleaved based on when they were last touched. Organized mode brings structure: all tasks for "Project Alpha" appear together, grouped by type, making it easier to see what's happening within each project at a glance.

### Key Concepts
- **Kanban column**: A vertical list of tasks grouped by status (e.g., "In Progress")
- **Sort order**: The rule that decides which task appears first in a column
- **Ephemeral state**: A setting that lives only while the app is running and resets on next launch
- **Handoff tasks**: Special tasks that are always pinned to the top of their column regardless of sort mode

---

## Intermediate Level

### Changes Overview
All changes are confined to two production files and one test file:

| File | Change |
|------|--------|
| `DashboardView.swift` | Added `ColumnSortOrder` enum, `sortOrder` state, `compareOrganized()` sort function, toolbar toggle button |
| `DashboardOrganizedSortTests.swift` | New test suite with 7 tests covering all sort tiers |
| `PromotionRollbackTests.swift` | Unrelated fix: `description: nil` changed to `description: ""` for type correctness |

### Implementation Approach
The implementation extends the existing `DashboardLogic.buildFilteredColumns()` function — the single entry point for filtering and sorting dashboard tasks. A new `sortOrder` parameter (defaulting to `.recent`) is threaded through from a `@State` property in `DashboardView`.

The sort comparator has a tiered structure:
1. **Tier 1 (unchanged)**: Done tasks sort before Abandoned in the terminal column
2. **Tier 2 (unchanged)**: Handoff tasks (Ready for Implementation, Ready for Review) pin to the top of their column
3. **Tier 3 (new branch)**: `.recent` uses date descending; `.organized` uses the multi-key comparator

The `compareOrganized()` function implements a cascade:
- Project name (ascending, case-insensitive via `localizedCaseInsensitiveCompare`)
- Task type (by `TaskType.allCases` declaration order: bug, feature, chore, research, documentation)
- Display ID (ascending, with `nil`/provisional IDs sorted last)
- `lastStatusChangeDate` descending as tiebreaker

The toolbar button is a simple `Button` that toggles between the two enum cases, placed in the existing filter toolbar group alongside project/type/milestone filters.

### Trade-offs
- **Enum inside `DashboardLogic` vs top-level model**: Correct choice — sort order is view-state, not domain model. It has no persistence and is only referenced by the dashboard.
- **Parameter on `buildFilteredColumns` vs separate sort step**: Adding the parameter keeps sort and filter as a single atomic operation, avoiding the risk of filtering with one sort but displaying with another.
- **Separate test file vs extending `DashboardFilterTests`**: Separate file keeps sort tests cohesive and avoids bloating the existing filter test suite.

---

## Expert Level

### Technical Deep Dive
The sort comparator satisfies strict weak ordering:
- **Irreflexivity**: `compareOrganized(a, a)` returns `false` — all tiers resolve to equality, and the date tiebreaker returns `false` for identical dates.
- **Transitivity**: Each tier uses a total order (string comparison, integer comparison, date comparison) and falls through only on equality.
- **Asymmetry**: Each tier's comparison is asymmetric.

The `nil` display ID handling uses a `switch` on the tuple `(lhs.permanentDisplayId, rhs.permanentDisplayId)`:
- `(value, value)` where values differ: compare ascending
- `(nil, some)`: return `false` (nil sorts after)
- `(some, nil)`: return `true`
- `(nil, nil)` or equal values: fall through to date tiebreaker via `default: break`

`localizedCaseInsensitiveCompare` is locale-dependent, so sort order may vary between devices with different locale settings. This is appropriate for user-facing display.

`TaskType.allCases.firstIndex(of:)` is O(k) where k is the number of enum cases (currently 5). Called O(n log n) times per column during sort, but with k=5 and typical column sizes of 10-30 tasks, this is negligible. A precomputed dictionary would add complexity for zero measurable benefit.

`filteredColumns` is a computed property evaluated twice per render (once for the column view, once for the empty-state overlay). At kanban scale this is negligible.

### Architecture Impact
- **Backward compatible**: The `sortOrder` parameter defaults to `.recent`, so all existing call sites (including existing tests) are unaffected.
- **No model changes**: No SwiftData schema changes, no CloudKit impact.
- **Filter independence**: Sort order is not considered a "filter" — `hasAnyFilter` excludes it, and the "Clear All" button does not reset sort order. This is the correct separation.
- **Extensibility**: Adding a third sort mode requires only a new enum case and comparator branch. The tiered sort structure (tiers 1-2 are mode-independent, tier 3 branches) cleanly separates shared invariants from mode-specific behavior.

### Potential Issues
- **Locale-dependent sorting**: Project names sort differently across locales. This is intentional but could surprise users who collaborate across regions (not a concern for a single-user app).
- **Empty project name fallback**: `lhs.project?.name ?? ""` handles nil projects defensively, though `matchesFilters()` already excludes nil-project tasks. If that filter logic changes, the sort won't crash but empty-named projects would sort first.
- **`TaskType` enum order dependency**: Reordering cases in `TaskType` changes the organized sort. This is documented in the spec as intentional — enum declaration order defines canonical type ordering.

---

## Completeness Assessment

### Fully Implemented
- Two sort modes (Recent/Organized) with correct multi-key comparison
- Toolbar toggle button with SF Symbols (clock/list.bullet)
- Accessibility support (identifier + label)
- Ephemeral state (resets on launch)
- Handoff-first and done-before-abandoned tiers preserved in both modes
- Provisional display ID sorting (nil after permanent)
- Date tiebreaker for equal organized keys
- 7 unit tests covering all sort tiers and edge cases

### Not Applicable / Out of Scope
- Persisting sort preference across launches (per spec: ephemeral)
- Per-column sort modes (per spec: single global toggle)
- Additional sort options beyond Recent and Organized
