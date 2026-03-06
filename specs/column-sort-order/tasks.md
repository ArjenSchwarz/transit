---
references:
    - specs/column-sort-order/smolspec.md
---
# Column Sort Order

## Implementation

- [ ] 1. ColumnSortOrder enum and buildFilteredColumns sort parameter <!-- id:1ouojhd -->
  - Add a ColumnSortOrder enum (.recent, .organized) inside DashboardLogic in DashboardView.swift.
  - Add a sortOrder parameter (defaulting to .recent) to buildFilteredColumns().
  - In the .sorted closure, after the existing handoff-first and done-before-abandoned tiers, branch on sortOrder: .recent keeps current lastStatusChangeDate descending; .organized compares by project name ascending (case-insensitive, nil-safe fallback to empty string), then TaskType enum order via allCases.firstIndex(of:), then permanentDisplayId ascending (nil sorts last), then lastStatusChangeDate descending as tiebreaker.
  - Verify: existing tests still pass unchanged (they use the default .recent sort).

- [ ] 2. Organized sort mode produces correct task ordering <!-- id:1ouojhe -->
  - Add tests in DashboardFilterTests.swift that call buildFilteredColumns with sortOrder: .organized.
  - Test cases: (1) tasks from different projects sort alphabetically by project name, (2) within same project, tasks sort by type in enum order (bug before feature before chore), (3) within same project and type, tasks sort by permanentDisplayId ascending, (4) tasks with nil permanentDisplayId sort after tasks with permanent IDs, (5) handoff-first and done-before-abandoned rules still apply in organized mode, (6) lastStatusChangeDate acts as tiebreaker when project/type/id are equal.
  - Blocked-by: 1ouojhd (ColumnSortOrder enum and buildFilteredColumns sort parameter)

- [ ] 3. Sort toggle button in dashboard toolbar <!-- id:1ouojhf -->
  - Add @State private var sortOrder: DashboardLogic.ColumnSortOrder = .recent to DashboardView.
  - Pass it to buildFilteredColumns() in the filteredColumns computed property.
  - Add a Button to the first ToolbarItemGroup (filter controls group) that toggles sortOrder between .recent and .organized.
  - Button icon should reflect the current mode (e.g. clock for Recent, list.bullet for Organized).
  - Add accessibilityIdentifier(dashboard.sortOrder) and a descriptive accessibilityLabel that includes the current mode name.
  - Verify: tapping the button changes the sort order of tasks in all columns.
  - Blocked-by: 1ouojhd (ColumnSortOrder enum and buildFilteredColumns sort parameter)

- [ ] 4. Sort toggle integrates correctly with filters and column views <!-- id:1ouojhg -->
  - Verify end-to-end behavior: sort mode works correctly alongside project/type/milestone filters.
  - Sort mode persists while switching between SingleColumnView and KanbanBoardView (orientation changes).
  - Sort mode resets to .recent on fresh launch.
  - Drag-and-drop still works correctly in both sort modes.
  - Run make test-quick and make lint to confirm all tests pass and no lint issues.
  - Blocked-by: 1ouojhe (Organized sort mode produces correct task ordering), 1ouojhf (Sort toggle button in dashboard toolbar)
