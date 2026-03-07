# Column Sort Order

## Overview

The kanban dashboard currently sorts tasks within columns by `lastStatusChangeDate` descending, with handoff tasks promoted to the top and done-before-abandoned in the terminal column. This change adds an alternative "organized" sort mode that groups tasks by project name, then task type, then display ID. A toolbar toggle lets the user switch between the two modes. Sort preference is ephemeral (resets on launch).

## Requirements

- The system MUST provide two sort modes for tasks within kanban columns: "Recent" (current date-based sort) and "Organized" (project, type, ID)
- The system MUST preserve handoff-first and done-before-abandoned sorting rules as the highest-priority tiers in both sort modes
- The system MUST sort "Organized" mode by: project name ascending (case-insensitive) > task type in enum declaration order (bug, feature, chore, research, documentation) > display ID ascending > `lastStatusChangeDate` descending (tiebreaker)
- The system MUST sort tasks with provisional (nil) display IDs after tasks with permanent display IDs within the same project/type group
- The system MUST provide a toolbar `Button` in the filter toolbar group to toggle between sort modes
- The system MUST default to "Recent" sort mode on launch (ephemeral state)
- The system MUST include `accessibilityIdentifier` and `accessibilityLabel` on the sort toggle button, following the existing toolbar button pattern
- The system SHOULD use a distinct SF Symbol per mode so the current state is visible at a glance (e.g., `clock` for Recent, `list.bullet` for Organized)

## Implementation Approach

- **Add `ColumnSortOrder` enum** with cases `.recent` and `.organized` inside the `DashboardLogic` enum in `Transit/Transit/Views/Dashboard/DashboardView.swift` (it's view-state, not model, so it belongs with the dashboard logic rather than in `TaskStatus.swift`)
- **Add `sortOrder` parameter** to `DashboardLogic.buildFilteredColumns()` at line 176 — defaults to `.recent` for backward compatibility
- **Add sort comparator** in the `.sorted` closure (line 211): after the existing handoff/terminal tiers, branch on `sortOrder` for the remaining comparison. Use `lastStatusChangeDate` descending as final tiebreaker in organized mode. Handle `project?.name` defensively (fallback to empty string) even though current filters exclude nil-project tasks
- **Add `@State private var sortOrder`** to `DashboardView` and pass it through `filteredColumns`
- **Add toolbar `Button`** in the first `ToolbarItemGroup` (line 86-98, the filter controls group) — a simple button that toggles between modes and swaps its icon/label to reflect current state
- **Add tests** in `Transit/TransitTests/DashboardFilterTests.swift` for the organized sort mode

**Existing patterns to follow:**
- Filter state: `@State private var selectedTypes: Set<TaskType> = []` (DashboardView.swift:8)
- `buildFilteredColumns` already accepts optional filter params with defaults (line 176-182)
- Toolbar buttons use `accessibilityIdentifier("dashboard.xxx")` and `accessibilityLabel` (e.g., lines 139-140)
- Toolbar groups use `ToolbarItemGroup(placement: .primaryAction)` with `ToolbarSpacer(.fixed)` for visual separation

**Dependencies:**
- `DashboardLogic.buildFilteredColumns()` — the single sort/filter entry point
- `TransitTask.project?.name`, `TransitTask.type`, `TransitTask.permanentDisplayId` — sort keys
- `TaskType.allCases` — used for enum-order comparison via `allCases.firstIndex(of:)`

**Out of Scope:**
- Persisting sort preference across launches (filter state is ephemeral per project convention)
- Per-column sort modes (single global toggle applies to all columns)
- Additional sort options beyond "Recent" and "Organized"

## Risks and Assumptions

- **Risk:** `TaskType.allCases` order could change if cases are reordered in the enum — **Mitigation:** This is intentional; enum declaration order defines the canonical type ordering
- **Risk:** `project?.name` could theoretically be nil if filter logic changes in the future — **Mitigation:** Sort comparator uses defensive fallback to empty string instead of force-unwrapping
- **Assumption:** Tasks with nil project are already excluded by `matchesFilters()` (line 233), so the organized sort comparator will always have a non-nil project in practice
- **Assumption:** The filter toolbar group has capacity for one more button; on iPhone, toolbar overflow handles any space constraints automatically
