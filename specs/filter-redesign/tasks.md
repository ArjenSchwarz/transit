---
references:
    - requirements.md
    - design.md
    - decision_log.md
metadata:
    transit_ticket: T-224
---
# Filter Redesign

## Pre-work

- [x] 1. Write unit tests for Binding+ToggleSet <!-- id:ovtjoe4 -->
  - Create `TransitTests/BindingToggleSetTests.swift` and `Extensions/Binding+ToggleSet.swift` with a stub that compiles but returns incorrect values
  - RED: Test inserting -- setting binding to `true` inserts element into set
  - RED: Test removing -- setting binding to `false` removes element from set
  - RED: Test reflecting state -- getting binding returns `true` when element is in set
  - Use Swift Testing framework with `@Suite(.serialized)`
  - Tests should fail at this point
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5)

- [x] 2. Implement Binding+ToggleSet extension <!-- id:ovtjoe5 -->
  - GREEN: Implement the generic `Binding<Set<T>>.contains(_:)` helper in `Extensions/Binding+ToggleSet.swift`
  - Creates a `Binding<Bool>` that toggles membership of an element in a `Set<Element: Hashable>`
  - See design.md Data Models > Binding Helper for the implementation
  - Run tests -- all should pass
  - Blocked-by: ovtjoe4 (Write unit tests for Binding+ToggleSet)
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5)

## Implement Filter Menus

- [ ] 3. Write tests for ProjectFilterMenu <!-- id:ovtjoe6 -->
  - Create `TransitTests/ProjectFilterMenuTests.swift` with a stub `ProjectFilterMenu` view that compiles
  - RED: Test that toggling a project adds/removes its ID from `selectedProjectIDs`
  - RED: Test that clear button empties `selectedProjectIDs`
  - RED: Test that count reflects number of selected projects
  - Tests should fail at this point
  - Blocked-by: ovtjoe5 (Implement Binding+ToggleSet extension)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5), [3.1](requirements.md#3.1), [7.1](requirements.md#7.1)

- [ ] 4. Implement ProjectFilterMenu <!-- id:ovtjoe7 -->
  - GREEN: Create `Views/Dashboard/ProjectFilterMenu.swift`
  - Platform-conditional: `Menu` with `.menuActionDismissBehavior(.disabled)` on iOS, `Button` + `.popover` with `List` on macOS (Decision 12)
  - Shared `@ViewBuilder` for `toggleContent` and `clearSection`
  - Adaptive label: text `Projects (N)` on regular width, icon-only `folder`/`folder.fill` with `.badge(count)` on compact (Decision 9)
  - Accept `let projects: [Project]` and `@Binding var selectedProjectIDs: Set<UUID>`
  - Add `.accessibilityIdentifier("dashboard.filter.projects")` and descriptive VoiceOver label
  - Run tests -- all should pass
  - Blocked-by: ovtjoe6 (Write tests for ProjectFilterMenu)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.8](requirements.md#1.8), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [7.1](requirements.md#7.1), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.4](requirements.md#8.4)

- [ ] 5. Write tests for TypeFilterMenu <!-- id:ovtjoe8 -->
  - Create `TransitTests/TypeFilterMenuTests.swift` with a stub `TypeFilterMenu` view that compiles
  - RED: Test that toggling a type adds/removes it from `selectedTypes`
  - RED: Test that clear button empties `selectedTypes`
  - RED: Test that count reflects number of selected types
  - Tests should fail at this point
  - Blocked-by: ovtjoe5 (Implement Binding+ToggleSet extension)
  - Stream: 2
  - Requirements: [1.2](requirements.md#1.2), [1.5](requirements.md#1.5), [3.1](requirements.md#3.1), [7.1](requirements.md#7.1)

- [ ] 6. Implement TypeFilterMenu <!-- id:ovtjoe9 -->
  - GREEN: Create `Views/Dashboard/TypeFilterMenu.swift`
  - Same platform-conditional pattern as ProjectFilterMenu (Decision 12)
  - Iterate `TaskType.allCases` for toggle content
  - Adaptive label: text `Types (N)` on regular, icon-only `tag`/`tag.fill` with `.badge(count)` on compact
  - Accept `@Binding var selectedTypes: Set<TaskType>`
  - Add `.accessibilityIdentifier("dashboard.filter.types")` and descriptive VoiceOver label
  - Run tests -- all should pass
  - Blocked-by: ovtjoe8 (Write tests for TypeFilterMenu)
  - Stream: 2
  - Requirements: [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.8](requirements.md#1.8), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [7.1](requirements.md#7.1), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.4](requirements.md#8.4)

- [ ] 7. Write tests for MilestoneFilterMenu <!-- id:ovtjoea -->
  - Create `TransitTests/MilestoneFilterMenuTests.swift` with a stub `MilestoneFilterMenu` view that compiles
  - RED: Test that toggling a milestone adds/removes its ID from `selectedMilestones`
  - RED: Test that clear button empties `selectedMilestones`
  - RED: Test that menu is hidden when no milestones are available and none selected
  - RED: Test milestone scoping to selected projects
  - Tests should fail at this point
  - Blocked-by: ovtjoe5 (Implement Binding+ToggleSet extension)
  - Stream: 2
  - Requirements: [1.3](requirements.md#1.3), [1.6](requirements.md#1.6), [1.9](requirements.md#1.9), [3.1](requirements.md#3.1), [7.1](requirements.md#7.1)

- [ ] 8. Implement MilestoneFilterMenu <!-- id:ovtjoeb -->
  - GREEN: Create `Views/Dashboard/MilestoneFilterMenu.swift`
  - Same platform-conditional pattern as ProjectFilterMenu (Decision 12)
  - Conditionally hidden when `availableMilestones.isEmpty && selectedMilestones.isEmpty` (req 1.9)
  - Scope available milestones to `selectedProjectIDs` via `milestoneService.milestonesForProject()` (req 1.6)
  - Accept `selectedProjectIDs` as `let` (read-only) -- milestone clearing via `.onChange` in DashboardView
  - Use `milestone.name` when single project selected, `milestone.displayName` when multiple
  - Adaptive label: text `Milestones (N)` on regular, icon-only `flag`/`flag.fill` with `.badge(count)` on compact
  - Add `.accessibilityIdentifier("dashboard.filter.milestones")` and descriptive VoiceOver label
  - Drop stale milestone display (Decision 11)
  - Run tests -- all should pass
  - Blocked-by: ovtjoea (Write tests for MilestoneFilterMenu)
  - Stream: 2
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.8](requirements.md#1.8), [1.9](requirements.md#1.9), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [7.1](requirements.md#7.1), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.4](requirements.md#8.4)

## Wire Up DashboardView

- [ ] 9. Replace filter popover with new toolbar layout in DashboardView <!-- id:ovtjoec -->
  - Modify `Views/Dashboard/DashboardView.swift`
  - Remove: `showFilter` state, `filterButton`, `activeFilterCount`, `activeFilterAccessibilityValue`, filter popover presentation
  - Add `clearAllButton`: clears projects, types, milestones, search when `hasAnyFilter` is true (Decision 5), hidden when inactive (Decision 8)
  - Add `hasAnyFilter` computed property checking all four filter states including `effectiveSearchText`
  - Restructure toolbar: [filter menus + clearAll] | [add + report] | [settings] separated by `ToolbarSpacer(.fixed)`
  - Migrate `.onChange(of: selectedProjectIDs) { selectedMilestones.removeAll() }` from FilterPopoverView into DashboardView body (req 1.7)
  - Add `.accessibilityIdentifier("dashboard.clearAllFilters")` and `.accessibilityLabel("Clear all filters")`
  - Blocked-by: ovtjoe7 (Implement ProjectFilterMenu), ovtjoe9 (Implement TypeFilterMenu), ovtjoeb (Implement MilestoneFilterMenu)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [1.7](requirements.md#1.7), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [8.3](requirements.md#8.3)

- [ ] 10. Add filtered empty state overlay <!-- id:ovtjoed -->
  - Add overlay in DashboardView alongside existing empty state
  - Condition: tasks exist but all filtered columns are empty and hasAnyFilter is true
  - Message: No matching tasks. Clear filters to see all tasks.
  - Reuse existing `EmptyStateView` component
  - Covers stale-milestone edge case (Decision 11) and general over-filtering (Decision 13)
  - Blocked-by: ovtjoec (Replace filter popover with new toolbar layout in DashboardView)
  - Stream: 1
  - Requirements: [1.9](requirements.md#1.9)

## Cleanup

- [ ] 11. Delete FilterPopoverView.swift <!-- id:ovtjoee -->
  - Delete `Views/Dashboard/FilterPopoverView.swift` entirely
  - Verify no remaining references to `FilterPopoverView` in the codebase
  - All its functionality is replaced by the three filter menus + DashboardView changes
  - Blocked-by: ovtjoec (Replace filter popover with new toolbar layout in DashboardView)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)

## Testing

- [ ] 12. Update UI tests for new filter accessibility identifiers <!-- id:ovtjoef -->
  - Update `TransitUITests/` to use new identifiers: `dashboard.filter.projects`, `dashboard.filter.types`, `dashboard.filter.milestones`, `dashboard.clearAllFilters`
  - Remove references to old `dashboard.filterButton` identifier
  - Add tests: testProjectFilterMenu, testTypeFilterMenu, testMilestoneFilterMenu, testClearAll, testMilestoneHiddenWhenNoMilestones, testMilestoneClearedOnProjectChange, testPerFilterClear
  - See design.md Testing Strategy for full test matrix
  - Blocked-by: ovtjoec (Replace filter popover with new toolbar layout in DashboardView), ovtjoed (Add filtered empty state overlay), ovtjoee (Delete FilterPopoverView.swift)
  - Stream: 1
  - Requirements: [8.2](requirements.md#8.2)

- [ ] 13. Build, lint, and run full test suite <!-- id:ovtjoeg -->
  - Run `make lint` to verify no SwiftLint issues
  - Run `make build` to verify compilation on iOS and macOS
  - Run `make test-quick` for unit tests (includes binding helper tests)
  - Run `make test-ui` for UI tests
  - Fix any issues found
  - Blocked-by: ovtjoef (Update UI tests for new filter accessibility identifiers)
  - Stream: 1
