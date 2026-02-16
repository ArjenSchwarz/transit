# Type Filter

## Overview

Add task type filtering to the kanban dashboard. Users can filter by one or more task types (bug, feature, chore, research, documentation) independently or combined with the existing project filter. This extends the current `FilterPopoverView` with a second section for type selection, following the same toggle-checkmark pattern used for projects.

## Requirements

- The system MUST allow filtering tasks by one or more `TaskType` values on the dashboard
- The system MUST support combining type filters with project filters (intersection: both must match)
- The system MUST show all tasks when no type filters are selected (same as project filter behavior)
- The system MUST display the filled filter icon when any filters are active (project or type), and show total active filter count in the badge
- The system MUST update the filter button's accessibility value to reflect total active filter count (project + type)
- The system MUST provide per-section "Clear" buttons in the filter popover (one for projects, one for types)
- The system SHOULD display type tint colors as a colored circle in the filter list for visual identification
- The system SHOULD provide a "Clear All" button when any filters from either section are active

## Implementation Approach

**Key files to modify:**

| File | Change |
|------|--------|
| `Transit/Views/Dashboard/DashboardView.swift` | Add `@State private var selectedTypes: Set<TaskType> = []`, pass to `FilterPopoverView` and `DashboardLogic.buildFilteredColumns()`, update badge and accessibility |
| `Transit/Views/Dashboard/FilterPopoverView.swift` | Add "Types" section with checkmark toggles for each `TaskType.allCases`, include tint color circle, add per-section "Clear" buttons and a "Clear All" button |
| `TransitTests/DashboardFilterTests.swift` | Add tests for type-only, combined, empty type, and zero-result combined filters |

**Pattern to follow:** The project filter in `DashboardLogic.buildFilteredColumns()` (lines 151-159 of `DashboardView.swift`). Type filtering applies the same logic: empty set means no filter, non-empty set means intersection.

**Filter combination logic in `buildFilteredColumns`:**
1. Start with all tasks that have a non-nil project (existing orphan guard)
2. If `selectedProjectIDs` is non-empty, keep only tasks whose project ID is in the set
3. If `selectedTypes` is non-empty, keep only tasks whose `type` is in the set
4. Steps 2 and 3 are AND-combined (both must pass when both are active)

**New parameter must have a default:** `selectedTypes: Set<TaskType> = []` so existing call sites (including all tests) remain source-compatible.

**Badge display:** The filter button uses the filled icon (`line.3.horizontal.decrease.circle.fill`) when `selectedProjectIDs.count + selectedTypes.count > 0`, and shows that total count in the label. Accessibility value is updated to match.

**Clear button design:** Each section ("Projects", "Types") gets its own "Clear" button that only appears when that section has selections. A "Clear All" button appears at the bottom when any filter from either section is active.

**Dependencies:** `TaskType` already conforms to `CaseIterable` and has `tintColor` — no model changes needed.

**Out of scope:**
- Persisting filter state across launches (filter is ephemeral per existing design decision)
- Adding type filter to App Intents query (separate concern)
- Changing the `TaskType` enum itself
- "No results" empty state when filters produce zero matches (exists today with project filters, deferred)

## Risks and Assumptions

- **Assumption:** `TaskType` conforms to `Hashable` (via `String` raw value) so it works in `Set<TaskType>` — verified, enums with raw values auto-conform
- **Risk:** FilterPopoverView growing too tall on small screens with both sections | **Mitigation:** The popover already has `.presentationDetents([.medium, .large])` and scrolls via `List`
- **Assumption:** `task.type` computed property (which falls back to `.feature` for unrecognized `typeRawValue`) is acceptable for filtering — this is existing behavior and not changed by this feature
