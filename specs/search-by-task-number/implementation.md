# Implementation: Search by Task Number (T-334)

## Beginner Level

### What Changed
The dashboard's search bar now finds tasks by their ID number (like "T-42"), not just by name or description. Before this change, if you knew a task's number, you had to scroll through the board to find it. Now you can type "T-42" or just "42" into the search box and it appears.

### Why It Matters
Transit assigns every task a unique number (T-1, T-2, etc.). These numbers are referenced in branch names, commit messages, and conversations. Being able to search by number makes it fast to jump to a specific task without scanning columns visually.

### Key Concepts
- **Display ID**: Each task has a human-readable identifier like "T-42". Internally this is stored as an integer (42) and formatted with the "T-" prefix for display.
- **Substring matching**: Searching "42" finds "T-42" because "42" is contained within "T-42". This is the same approach used for name and description search.
- **Conjunctive filters**: The search box works alongside project, type, and milestone filters. All active filters must match (AND logic) -- search narrows results within the currently selected filters.

---

## Intermediate Level

### Changes Overview
One production file changed (`DashboardView.swift`), plus four new unit tests and spec documents.

| File | Change |
|------|--------|
| `Transit/Views/Dashboard/DashboardView.swift:253` | Added `displayIdMatch` to the search predicate |
| `Transit/TransitTests/DashboardSearchTests.swift` | Four new tests covering full ID, bare number, case-insensitivity, and filter combination |
| `CHANGELOG.md` | Two new entries under Unreleased/Added |
| `specs/search-by-task-number/` | Smolspec and task list |

### Implementation Approach
The `matchesFilters()` function in `DashboardLogic` already had a pattern for text search: compute `nameMatch` and `descMatch` booleans, then `guard` that at least one is true. The change adds a third boolean `displayIdMatch` using the same `localizedCaseInsensitiveContains` method on `task.displayID.formatted`.

`DisplayID.formatted` returns `"T-42"` for permanent IDs and `"T-•"` (unicode bullet U+2022) for provisional ones. Since `localizedCaseInsensitiveContains` does substring matching, searching "42" naturally matches "T-42", and "t-42" matches case-insensitively. No parsing of the search input is needed.

Tests set `task.permanentDisplayId` directly (it's a stored `Int?` on the model) since the `makeTask` helper creates tasks with provisional display IDs by default.

### Trade-offs
- Substring matching means "4" matches T-4, T-14, T-40-49, etc. This is consistent with name/description search behavior and acceptable for a single-user app with hundreds of tasks.
- No special "exact ID" mode was added -- the simplicity of one matching approach outweighs the minor cost of broader results.

---

## Expert Level

### Technical Deep Dive
The change is a single line addition to a pure function (`matchesFilters` on `DashboardLogic` enum). `displayID.formatted` is a computed property that does simple string interpolation (`"T-\(id)"`) -- no allocations beyond the result string. Called per-task per-keystroke, but with expected dataset sizes (hundreds of tasks), this is negligible.

The filter chain structure -- sequential `if/guard` blocks for project, type, milestone, then search text -- means display ID search participates in the existing conjunctive AND logic without any structural changes. The OR is only within the search text block (name OR description OR displayId).

### Architecture Impact
None. This is a leaf change to an existing pure function. No new types, no new dependencies, no protocol changes. The `DisplayID` type and its `formatted` property already existed.

### Potential Issues
- **Provisional IDs**: Tasks without a permanent ID have `formatted` returning `"T-•"` (U+2022). Searching "T-" matches these, which is acceptable since "T-" also matches any permanent ID.
- **Numeric false positives**: A task named "42 bugs found" would match search "42" via name match, and T-42 would also match via display ID. Both appearing in results is correct behavior.
- **No milestone filter in test**: The combination test uses project + type filters but not milestone. This is sufficient because the filter chain is sequential guards -- adding milestone wouldn't exercise different code paths.

---

## Completeness Assessment

**Fully implemented:**
- Dashboard search matches formatted display ID (T-42) -- requirement met
- Bare number search (42) matches via substring -- requirement met
- Case-insensitive matching (t-42) -- requirement met
- Existing name/description search unchanged -- verified by existing tests passing
- Search combines with project, type, and milestone filters -- structural guarantee from sequential guard chain, tested with project + type

**Partially implemented:** None

**Missing:** None

All four spec requirements are satisfied. The implementation follows the spec's recommended approach exactly.
