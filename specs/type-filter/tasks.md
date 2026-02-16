---
references:
    - specs/type-filter/smolspec.md
---
# Type Filter

## Core Logic

- [x] 1. Type filter parameter added to buildFilteredColumns with AND-combination logic

- [x] 2. Type-only filtering returns only tasks matching selected types; empty set returns all tasks

- [x] 3. Combined project + type filtering returns intersection (both must match); zero-result case produces empty columns

## UI

- [ ] 4. FilterPopoverView shows Types section with checkmark toggles and tint color circles for each TaskType

- [ ] 5. Per-section Clear buttons appear when that section has selections; Clear All button appears when any filter is active

- [ ] 6. DashboardView passes selectedTypes state to FilterPopoverView and buildFilteredColumns

- [ ] 7. Filter toolbar button badge shows total active count (project + type) with filled icon; accessibility value updated to match

- [ ] 8. Build succeeds on both iOS and macOS targets with no warnings
