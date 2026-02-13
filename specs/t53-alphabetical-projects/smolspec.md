# T-53: Alphabetically Order Project Lists

**Type**: Feature (minor)
**Status**: Ready for implementation

## Problem

Project lists in the UI appear in insertion order (no sort descriptors on `@Query`). The App Intents layer already sorts alphabetically via `SortDescriptor(\Project.name)`, creating an inconsistency.

## Solution

Add `sort: \Project.name` to all four `@Query` declarations that fetch projects for display:

1. `SettingsView.swift` — project management list
2. `AddTaskSheet.swift` — project picker for new tasks
3. `TaskEditView.swift` — project picker for editing tasks
4. `DashboardView.swift` — provides projects to filter popover

## Out of Scope

- `ProjectService.findProject()` — fetches for lookup by name/ID, not display order
- `ProjectEntityQuery.suggestedEntities()` — already sorted correctly
