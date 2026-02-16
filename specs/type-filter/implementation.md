# Type Filter — Implementation Explanation

## Beginner Level

### What Changed
The Transit kanban dashboard already let you filter tasks by project (e.g. "only show tasks from Project Alpha"). This change adds a second filter dimension: **task type**. You can now filter by bug, feature, chore, research, or documentation — or any combination of those.

When you tap the filter button, the popover now has two sections: **Projects** and **Types**. Each type shows a colored circle matching its tint color and a checkmark toggle. Both filters work together — if you select Project Alpha *and* Bug, you'll only see bugs that belong to Project Alpha.

### Why It Matters
As the number of tasks grows, being able to narrow the board to "just the bugs" or "just the research tasks" makes the dashboard more useful. The filter badge in the toolbar updates to show the total number of active filters across both sections, so you always know filtering is active.

### Key Concepts
- **AND combination**: When both project and type filters are active, a task must match *both* to appear. This is intersection logic — not "show bugs OR Project Alpha tasks", but "show bugs that are IN Project Alpha".
- **Empty set = no filter**: If you don't select any types, all types pass through. Same for projects. This means the filter is opt-in.

---

## Intermediate Level

### Changes Overview
Three files modified, one test file extended:

| File | Summary |
|------|---------|
| `DashboardView.swift` | Added `@State selectedTypes: Set<TaskType>`, wired to `FilterPopoverView` and `buildFilteredColumns`. Extracted `activeFilterCount` computed property for badge and accessibility. |
| `FilterPopoverView.swift` | Added `@Binding selectedTypes`, a "Types" section with `ForEach(TaskType.allCases)`, per-section "Clear" buttons, and a "Clear All" button. |
| `DashboardFilterTests.swift` | 5 new tests: single type, multi-type, empty set passthrough, combined project+type intersection, zero-result combined. |

### Implementation Approach
The implementation mirrors the existing project filter pattern. `buildFilteredColumns` gained a `selectedTypes: Set<TaskType> = []` parameter with a default value to maintain source compatibility. The filter logic is a single `allTasks.filter { }` closure that applies three sequential guards: orphan exclusion, project membership, and type membership. This is a refactor from the previous two-branch approach (empty vs non-empty project set) into a unified filter pipeline.

The `FilterPopoverView` wraps the existing project list in a `Section` (it previously had none) and adds a second `Section` for types. Each section gets a conditional "Clear" button in its header. A "Clear All" button at the bottom appears when `hasAnyFilter` is true.

### Trade-offs
- **Single filter closure vs chained filters**: Combining all predicates in one `.filter` call is simpler and avoids allocating intermediate arrays, at the cost of slightly more complex guard logic. For the expected task counts (tens to low hundreds), this is the right trade-off.
- **Default parameter for backwards compatibility**: Using `selectedTypes: Set<TaskType> = []` avoids updating every existing call site, but means the parameter is invisible in code that doesn't use it. Acceptable given there's only one call site in production code.

---

## Expert Level

### Technical Deep Dive
The core change to `buildFilteredColumns` replaces the previous branching approach (separate code paths for "has project filter" vs "no project filter") with a linear guard chain. Each filter is independent and short-circuits with `return false` on mismatch. The refactoring is semantically equivalent for the project-only case and extends naturally to the type dimension.

`TaskType` is a `String`-backed enum, so it auto-conforms to `Hashable` — `Set<TaskType>` works without any additional conformance. The `task.type` computed property falls back to `.feature` for unrecognised raw values; this existing behaviour means a task with a corrupted `typeRawValue` would still appear under the "Feature" type filter. This is documented in the smolspec as an accepted assumption.

The `activeFilterCount` computed property sums both set sizes rather than checking a boolean, which means the badge shows "3" if you have 2 projects and 1 type selected. This matches the spec requirement for total count display.

### Architecture Impact
Minimal. The change stays within the existing dashboard view layer. No model changes, no service changes, no new files. The `FilterPopoverView` API changed (new `selectedTypes` binding), but it's only instantiated in one place.

Filter state remains ephemeral (`@State`) per the existing design decision — no persistence across launches. If type filter persistence is added later, the same pattern used for project filters would apply.

### Potential Issues
- **Type fallback in filtering**: Tasks with unrecognised `typeRawValue` map to `.feature` via the computed property. If a user filters for `.feature`, they'll get these "unknown type" tasks too. This is pre-existing behaviour, not introduced here.
- **Badge count semantics**: The badge shows the sum of individual selections (e.g. 2 projects + 3 types = 5), not the number of active filter dimensions (which would be 2). The count-of-selections approach is more informative but could look high. The spec explicitly requires this behaviour.

---

## Completeness Assessment

### Fully Implemented
- All 6 MUST requirements verified against implementation
- Both 2 SHOULD requirements implemented (tint color circles, Clear All button)
- All 8 tasks from the task list marked complete
- 5 new unit tests covering all specified scenarios
- Build passes on both iOS and macOS with no warnings
- Lint passes with no issues

### Not Applicable / Out of Scope (per spec)
- Filter state persistence (ephemeral by design)
- Type filter in App Intents query (separate feature)
- "No results" empty state (deferred, same as project filter)
- Changes to the `TaskType` enum itself

### Requirement Traceability

| Requirement | Implementation | Test |
|------------|---------------|------|
| Filter by one or more TaskType values | `buildFilteredColumns` type guard (DashboardView:170-172) | `typeFilterReducesToSelectedTypes`, `typeFilterWithMultipleTypesReturnsAll` |
| Combine with project filter (intersection) | Sequential guards in single filter closure (DashboardView:159-174) | `combinedProjectAndTypeFilterReturnsIntersection` |
| Empty type set shows all tasks | `if !selectedTypes.isEmpty` guard (DashboardView:170) | `emptyTypeFilterShowsAllTasks` |
| Filled icon + total count badge | `activeFilterCount` computed property (DashboardView:96-98) | — (UI, not unit-testable) |
| Accessibility value reflects count | `.accessibilityValue("\(activeFilterCount)")` (DashboardView:111) | — (UI, verifiable via UI tests) |
| Per-section Clear buttons | Section headers with conditional Clear buttons (FilterPopoverView:40-49, 77-87) | — (UI) |
| Tint color circles | `Circle().fill(type.tintColor)` (FilterPopoverView:62-63) | — (UI) |
| Clear All button | `if hasAnyFilter` conditional (FilterPopoverView:90-96) | — (UI) |
