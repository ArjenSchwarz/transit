---
references:
    - specs/transit-v1/requirements.md
    - specs/transit-v1/design.md
    - specs/transit-v1/decision_log.md
---
# Transit V1 Implementation

## Pre-work

- [x] 1. Initialize Xcode project structure and test targets <!-- id:gn0obfn -->
  - Stream: 1
  - Requirements: [14.1](requirements.md#14.1)

## Data Models & Enums

- [x] 2. Implement TaskStatus and DashboardColumn enums <!-- id:gn0obfo -->
  - Blocked-by: gn0obfn (Initialize Xcode project structure and test targets)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [13.2](requirements.md#13.2)

- [x] 3. Write unit tests for TaskStatus column mapping, isHandoff, isTerminal, shortLabel, and DashboardColumn.primaryStatus <!-- id:gn0obfp -->
  - Blocked-by: gn0obfo (Implement TaskStatus and DashboardColumn enums)
  - Stream: 1
  - Requirements: [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [7.1](requirements.md#7.1), [7.4](requirements.md#7.4)

- [x] 4. Implement TaskType enum <!-- id:gn0obfq -->
  - Blocked-by: gn0obfn (Initialize Xcode project structure and test targets)
  - Stream: 1
  - Requirements: [2.5](requirements.md#2.5)

- [x] 5. Implement DisplayID enum with formatted property <!-- id:gn0obfr -->
  - Blocked-by: gn0obfn (Initialize Xcode project structure and test targets)
  - Stream: 1
  - Requirements: [3.6](requirements.md#3.6), [3.7](requirements.md#3.7)

- [x] 6. Write unit tests for DisplayID formatting (T-N and T-bullet) <!-- id:gn0obfs -->
  - Blocked-by: gn0obfr (Implement DisplayID enum with formatted property)
  - Stream: 1
  - Requirements: [3.6](requirements.md#3.6), [3.7](requirements.md#3.7)

- [x] 7. Implement Color+Codable extension (hex string conversion) <!-- id:gn0obft -->
  - Blocked-by: gn0obfn (Initialize Xcode project structure and test targets)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1)

- [x] 8. Implement Date+TransitHelpers extension (48-hour window computation) <!-- id:gn0obfu -->
  - Blocked-by: gn0obfn (Initialize Xcode project structure and test targets)
  - Stream: 1
  - Requirements: [5.6](requirements.md#5.6)

- [x] 9. Define Project @Model with optional relationship and CloudKit-compatible fields <!-- id:gn0obfv -->
  - Blocked-by: gn0obft (Implement Color+Codable extension (hex string conversion))
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3)

- [x] 10. Define TransitTask @Model with optional relationship, computed status/type, DisplayID, metadata JSON, and creationDate <!-- id:gn0obfw -->
  - Blocked-by: gn0obfo (Implement TaskStatus and DashboardColumn enums), gn0obfq (Implement TaskType enum), gn0obfr (Implement DisplayID enum with formatted property), gn0obfv (Define Project @Model with optional relationship and CloudKit-compatible fields)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.6](requirements.md#2.6), [3.4](requirements.md#3.4)

## Domain Services

- [x] 11. Implement StatusEngine with initializeNewTask and applyTransition <!-- id:gn0obfx -->
  - Blocked-by: gn0obfw (Define TransitTask @Model with optional relationship, computed status/type, DisplayID, metadata JSON, and creationDate)
  - Stream: 1
  - Requirements: [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [4.8](requirements.md#4.8), [11.9](requirements.md#11.9)

- [ ] 12. Write StatusEngine unit tests and property-based tests for transition invariants <!-- id:gn0obfy -->
  - Blocked-by: gn0obfx (Implement StatusEngine with initializeNewTask and applyTransition)
  - Stream: 1
  - Requirements: [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.8](requirements.md#4.8)

- [x] 13. Implement DisplayIDAllocator with CloudKit counter, optimistic locking, provisional IDs, and per-task promotion <!-- id:gn0obfz -->
  - Blocked-by: gn0obfw (Define TransitTask @Model with optional relationship, computed status/type, DisplayID, metadata JSON, and creationDate)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.8](requirements.md#3.8)

- [ ] 14. Write DisplayIDAllocator tests (provisional, promotion ordering, partial failure, conflict retry) <!-- id:gn0obg0 -->
  - Blocked-by: gn0obfz (Implement DisplayIDAllocator with CloudKit counter, optimistic locking, provisional IDs, and per-task promotion)
  - Stream: 1
  - Requirements: [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.8](requirements.md#3.8)

- [ ] 15. Implement TaskService (createTask, updateStatus, abandon, restore, findByDisplayID) <!-- id:gn0obg1 -->
  - Blocked-by: gn0obfx (Implement StatusEngine with initializeNewTask and applyTransition), gn0obfz (Implement DisplayIDAllocator with CloudKit counter, optimistic locking, provisional IDs, and per-task promotion)
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4), [2.7](requirements.md#2.7), [4.2](requirements.md#4.2), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [10.6](requirements.md#10.6), [17.2](requirements.md#17.2)

- [ ] 16. Write TaskService tests (creation, status changes, abandon/restore, constraint enforcement) <!-- id:gn0obg2 -->
  - Blocked-by: gn0obg1 (Implement TaskService (createTask, updateStatus, abandon, restore, findByDisplayID)), abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4), [2.7](requirements.md#2.7), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [10.6](requirements.md#10.6)

- [x] 17. Implement ProjectService (createProject, findProject with case-insensitive matching, activeTaskCount) <!-- id:gn0obg3 -->
  - Blocked-by: gn0obfw (Define TransitTask @Model with optional relationship, computed status/type, DisplayID, metadata JSON, and creationDate)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [12.3](requirements.md#12.3), [16.3](requirements.md#16.3), [16.4](requirements.md#16.4)

- [ ] 18. Write ProjectService tests (creation, find by ID/name, ambiguous match, active count, no delete method) <!-- id:gn0obg4 -->
  - Blocked-by: gn0obg3 (Implement ProjectService (createProject, findProject with case-insensitive matching, activeTaskCount))
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [1.6](requirements.md#1.6), [12.3](requirements.md#12.3), [16.4](requirements.md#16.4)

## UI - Shared Components

- [ ] 19. Implement EmptyStateView (reusable empty state messaging) <!-- id:gn0obg5 -->
  - Blocked-by: gn0obfn (Initialize Xcode project structure and test targets)
  - Stream: 2
  - Requirements: [20.1](requirements.md#20.1), [20.2](requirements.md#20.2), [20.4](requirements.md#20.4)

- [ ] 20. Implement ProjectColorDot (rounded square with project color) <!-- id:gn0obg6 -->
  - Blocked-by: gn0obfn (Initialize Xcode project structure and test targets)
  - Stream: 2
  - Requirements: [6.2](requirements.md#6.2), [12.3](requirements.md#12.3)

- [ ] 21. Implement TypeBadge (tinted badge for task type) <!-- id:gn0obg7 -->
  - Blocked-by: gn0obfq (Implement TaskType enum)
  - Stream: 2
  - Requirements: [6.1](requirements.md#6.1)

- [ ] 22. Implement MetadataSection (key-value display and edit) <!-- id:gn0obg8 -->
  - Blocked-by: gn0obfn (Initialize Xcode project structure and test targets)
  - Stream: 2
  - Requirements: [11.1](requirements.md#11.1), [11.8](requirements.md#11.8)

## UI - Dashboard

- [ ] 23. Implement TaskCardView with glass effect, project color border, display ID, and type badge <!-- id:gn0obg9 -->
  - Blocked-by: gn0obfw (Define TransitTask @Model with optional relationship, computed status/type, DisplayID, metadata JSON, and creationDate), gn0obg6 (Implement ProjectColorDot (rounded square with project color)), rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, gn0obg7 (Implement TypeBadge (tinted badge for task type))
  - Stream: 2
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [5.7](requirements.md#5.7)

- [ ] 24. Implement ColumnView with header (name + count), done/abandoned separator, abandoned styling, and per-column empty state <!-- id:gn0obga -->
  - Blocked-by: gn0obg9 (Implement TaskCardView with glass effect, project color border, display ID, and type badge), gn0obg5 (Implement EmptyStateView (reusable empty state messaging))
  - Stream: 2
  - Requirements: [5.5](requirements.md#5.5), [5.7](requirements.md#5.7), [5.9](requirements.md#5.9), [14.3](requirements.md#14.3), [20.2](requirements.md#20.2)

- [ ] 25. Implement KanbanBoardView (multi-column horizontal scrolling board) <!-- id:gn0obgb -->
  - Blocked-by: gn0obga (Implement ColumnView with header (name + count), done/abandoned separator, abandoned styling, and per-column empty state), styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling
  - Stream: 2
  - Requirements: [5.2](requirements.md#5.2), [13.6](requirements.md#13.6)

- [ ] 26. Implement SingleColumnView with segmented control (short labels, counts, default Active segment) <!-- id:gn0obgc -->
  - Blocked-by: gn0obga (Implement ColumnView with header (name + count), done/abandoned separator, abandoned styling, and per-column empty state), styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling, styling
  - Stream: 2
  - Requirements: [13.1](requirements.md#13.1), [13.2](requirements.md#13.2), [13.3](requirements.md#13.3), [13.7](requirements.md#13.7)

- [ ] 27. Implement FilterPopoverView with multi-select project checkboxes and Clear action <!-- id:gn0obgd -->
  - Blocked-by: gn0obfv (Define Project @Model with optional relationship and CloudKit-compatible fields), gn0obg6 (Implement ProjectColorDot (rounded square with project color)), rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project
  - Stream: 2
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.5](requirements.md#9.5), [9.6](requirements.md#9.6)

- [ ] 28. Implement DashboardView with GeometryReader layout switching, column filtering/sorting, project filter, toolbar, and global empty state <!-- id:gn0obge -->
  - Blocked-by: gn0obgb (Implement KanbanBoardView (multi-column horizontal scrolling board)), gn0obgc (Implement SingleColumnView with segmented control (short labels, counts, default Active segment)), control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, control, default, gn0obgd (Implement FilterPopoverView with multi-select project checkboxes and Clear action), gn0obg1 (Implement TaskService (createTask, updateStatus, abandon, restore, findByDisplayID)), abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, gn0obg3 (Implement ProjectService (createProject, findProject with case-insensitive matching, activeTaskCount))
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.6](requirements.md#5.6), [5.8](requirements.md#5.8), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [9.4](requirements.md#9.4), [13.4](requirements.md#13.4), [13.5](requirements.md#13.5), [20.1](requirements.md#20.1)

- [ ] 29. Implement drag-and-drop between columns (Transferable UUID, drop targets, primaryStatus assignment) <!-- id:gn0obgf -->
  - Blocked-by: gn0obge (Implement DashboardView with GeometryReader layout switching, column filtering/sorting, project filter, toolbar, and global empty state)
  - Stream: 2
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)

- [ ] 30. Write unit tests for dashboard column filtering, 48-hour cutoff, sorting (handoff first, done before abandoned), and project filter logic <!-- id:gn0obgg -->
  - Blocked-by: gn0obge (Implement DashboardView with GeometryReader layout switching, column filtering/sorting, project filter, toolbar, and global empty state)
  - Stream: 2
  - Requirements: [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [5.8](requirements.md#5.8), [9.2](requirements.md#9.2), [9.5](requirements.md#9.5)

- [ ] 31. Write unit tests for drag-and-drop status mapping (base status per column, Done not Abandoned, backward drag, completionDate clearing) <!-- id:gn0obgh -->
  - Blocked-by: gn0obgf (Implement drag-and-drop between columns (Transferable UUID, drop targets, primaryStatus assignment)), between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets, between, columns, targets
  - Stream: 2
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)

## UI - Task Management

- [ ] 32. Implement AddTaskSheet with project picker, name/description/type fields, validation, and platform-adaptive presentation <!-- id:gn0obgi -->
  - Blocked-by: gn0obg1 (Implement TaskService (createTask, updateStatus, abandon, restore, findByDisplayID)), abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, gn0obg3 (Implement ProjectService (createProject, findProject with case-insensitive matching, activeTaskCount)), gn0obg6 (Implement ProjectColorDot (rounded square with project color)), rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project
  - Stream: 2
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [10.4](requirements.md#10.4), [10.5](requirements.md#10.5), [10.6](requirements.md#10.6), [10.7](requirements.md#10.7), [20.3](requirements.md#20.3)

- [ ] 33. Implement TaskDetailView (read-only display of all fields, Abandon/Restore buttons, platform-adaptive presentation) <!-- id:gn0obgj -->
  - Blocked-by: gn0obfw (Define TransitTask @Model with optional relationship, computed status/type, DisplayID, metadata JSON, and creationDate), gn0obg6 (Implement ProjectColorDot (rounded square with project color)), rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, gn0obg7 (Implement TypeBadge (tinted badge for task type))
  - Stream: 2
  - Requirements: [11.1](requirements.md#11.1), [11.2](requirements.md#11.2), [11.4](requirements.md#11.4), [11.5](requirements.md#11.5), [11.6](requirements.md#11.6), [11.7](requirements.md#11.7)

- [ ] 34. Implement TaskEditView (editable name, description, type, project, status picker with side effects, metadata editing) <!-- id:gn0obgk -->
  - Blocked-by: gn0obgj (Implement TaskDetailView (read-only display of all fields, Abandon/Restore buttons, platform-adaptive presentation)), display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, display, buttons, gn0obg1 (Implement TaskService (createTask, updateStatus, abandon, restore, findByDisplayID)), abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, gn0obg8 (Implement MetadataSection (key-value display and edit)), display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display, display
  - Stream: 2
  - Requirements: [11.3](requirements.md#11.3), [11.8](requirements.md#11.8), [11.9](requirements.md#11.9), [2.4](requirements.md#2.4)

## UI - Settings

- [ ] 35. Implement SettingsView with Projects section (color swatch, name, active count, add button) and General section (About, sync toggle) <!-- id:gn0obgl -->
  - Blocked-by: gn0obg3 (Implement ProjectService (createProject, findProject with case-insensitive matching, activeTaskCount)), gn0obg5 (Implement EmptyStateView (reusable empty state messaging)), gn0obg6 (Implement ProjectColorDot (rounded square with project color)), rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project
  - Stream: 2
  - Requirements: [12.1](requirements.md#12.1), [12.2](requirements.md#12.2), [12.3](requirements.md#12.3), [12.5](requirements.md#12.5), [12.6](requirements.md#12.6), [12.7](requirements.md#12.7), [12.8](requirements.md#12.8), [20.4](requirements.md#20.4)

- [ ] 36. Implement ProjectEditView (create/edit form with name, description, git repo, color picker) <!-- id:gn0obgm -->
  - Blocked-by: gn0obg3 (Implement ProjectService (createProject, findProject with case-insensitive matching, activeTaskCount)), gn0obg6 (Implement ProjectColorDot (rounded square with project color)), rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project, rounded, project
  - Stream: 2
  - Requirements: [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [12.4](requirements.md#12.4)

## App Integration

- [ ] 37. Implement TransitApp entry point (ModelContainer with CloudKit, service instantiation, environment injection, AppDependencyManager registration) <!-- id:gn0obgn -->
  - Blocked-by: gn0obg1 (Implement TaskService (createTask, updateStatus, abandon, restore, findByDisplayID)), abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, gn0obg3 (Implement ProjectService (createProject, findProject with case-insensitive matching, activeTaskCount)), gn0obfz (Implement DisplayIDAllocator with CloudKit counter, optimistic locking, provisional IDs, and per-task promotion)
  - Stream: 1
  - Requirements: [15.1](requirements.md#15.1), [15.2](requirements.md#15.2)

- [ ] 38. Wire navigation (NavigationStack, sheet presentations for AddTask/Detail, popover for filter, push for Settings) <!-- id:gn0obgo -->
  - Blocked-by: gn0obge (Implement DashboardView with GeometryReader layout switching, column filtering/sorting, project filter, toolbar, and global empty state), gn0obgi (Implement AddTaskSheet with project picker, name/description/type fields, validation, and platform-adaptive presentation), gn0obgl (Implement SettingsView with Projects section (color swatch, name, active count, add button) and General section (About, sync toggle)), section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, section, gn0obgn (Implement TransitApp entry point (ModelContainer with CloudKit, service instantiation, environment injection, AppDependencyManager registration)), service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [6.4](requirements.md#6.4), [8.1](requirements.md#8.1), [10.4](requirements.md#10.4), [10.5](requirements.md#10.5), [11.6](requirements.md#11.6), [11.7](requirements.md#11.7), [12.1](requirements.md#12.1)

- [ ] 39. Implement NWPathMonitor connectivity tracking and promotion triggers (app launch, scenePhase active, connectivity restore) <!-- id:gn0obgp -->
  - Blocked-by: gn0obgn (Implement TransitApp entry point (ModelContainer with CloudKit, service instantiation, environment injection, AppDependencyManager registration)), service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, gn0obfz (Implement DisplayIDAllocator with CloudKit counter, optimistic locking, provisional IDs, and per-task promotion)
  - Stream: 1
  - Requirements: [3.5](requirements.md#3.5), [15.5](requirements.md#15.5)

- [ ] 40. Implement CloudKit sync toggle (cloudKitContainerOptions nil/restore, persistent history delta sync on re-enable) <!-- id:gn0obgq -->
  - Blocked-by: gn0obgn (Implement TransitApp entry point (ModelContainer with CloudKit, service instantiation, environment injection, AppDependencyManager registration)), service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service, service
  - Stream: 1
  - Requirements: [12.7](requirements.md#12.7), [12.9](requirements.md#12.9), [15.4](requirements.md#15.4)

## App Intents

- [ ] 41. Implement IntentError enum with JSON encoding via JSONSerialization <!-- id:gn0obgr -->
  - Blocked-by: gn0obfn (Initialize Xcode project structure and test targets)
  - Stream: 3
  - Requirements: [19.1](requirements.md#19.1), [19.2](requirements.md#19.2), [19.3](requirements.md#19.3)

- [ ] 42. Write IntentError tests (all error codes, JSON structure, special character escaping) <!-- id:gn0obgs -->
  - Blocked-by: gn0obgr (Implement IntentError enum with JSON encoding via JSONSerialization)
  - Stream: 3
  - Requirements: [19.1](requirements.md#19.1), [19.2](requirements.md#19.2)

- [ ] 43. Implement CreateTaskIntent (JSON parse, project resolution, validation, task creation, openAppWhenRun, @MainActor perform) <!-- id:gn0obgt -->
  - Blocked-by: gn0obgr (Implement IntentError enum with JSON encoding via JSONSerialization), gn0obg1 (Implement TaskService (createTask, updateStatus, abandon, restore, findByDisplayID)), abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, gn0obg3 (Implement ProjectService (createProject, findProject with case-insensitive matching, activeTaskCount))
  - Stream: 3
  - Requirements: [16.1](requirements.md#16.1), [16.2](requirements.md#16.2), [16.3](requirements.md#16.3), [16.4](requirements.md#16.4), [16.5](requirements.md#16.5), [16.6](requirements.md#16.6), [16.7](requirements.md#16.7), [16.8](requirements.md#16.8)

- [ ] 44. Write CreateTaskIntent tests (valid input, missing name, invalid type, ambiguous project, projectId preference) <!-- id:gn0obgu -->
  - Blocked-by: gn0obgt (Implement CreateTaskIntent (JSON parse, project resolution, validation, task creation, openAppWhenRun, @MainActor perform)), project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project
  - Stream: 3
  - Requirements: [16.3](requirements.md#16.3), [16.4](requirements.md#16.4), [16.5](requirements.md#16.5), [16.6](requirements.md#16.6), [16.8](requirements.md#16.8)

- [ ] 45. Implement UpdateStatusIntent (JSON parse, task lookup by displayId, status validation, transition via TaskService) <!-- id:gn0obgv -->
  - Blocked-by: gn0obgr (Implement IntentError enum with JSON encoding via JSONSerialization), gn0obg1 (Implement TaskService (createTask, updateStatus, abandon, restore, findByDisplayID)), abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore
  - Stream: 3
  - Requirements: [17.1](requirements.md#17.1), [17.2](requirements.md#17.2), [17.3](requirements.md#17.3), [17.4](requirements.md#17.4), [17.5](requirements.md#17.5), [17.6](requirements.md#17.6)

- [ ] 46. Write UpdateStatusIntent tests (valid update, unknown displayId, invalid status, response format) <!-- id:gn0obgw -->
  - Blocked-by: gn0obgv (Implement UpdateStatusIntent (JSON parse, task lookup by displayId, status validation, transition via TaskService))
  - Stream: 3
  - Requirements: [17.4](requirements.md#17.4), [17.5](requirements.md#17.5), [17.6](requirements.md#17.6)

- [ ] 47. Implement QueryTasksIntent (JSON parse, optional filters, SwiftData predicate building, JSON array response) <!-- id:gn0obgx -->
  - Blocked-by: gn0obgr (Implement IntentError enum with JSON encoding via JSONSerialization), gn0obg1 (Implement TaskService (createTask, updateStatus, abandon, restore, findByDisplayID)), abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, abandon, restore, gn0obg3 (Implement ProjectService (createProject, findProject with case-insensitive matching, activeTaskCount))
  - Stream: 3
  - Requirements: [18.1](requirements.md#18.1), [18.2](requirements.md#18.2), [18.3](requirements.md#18.3), [18.4](requirements.md#18.4), [18.5](requirements.md#18.5)

- [ ] 48. Write QueryTasksIntent tests (no filters returns all, status filter, project filter, PROJECT_NOT_FOUND) <!-- id:gn0obgy -->
  - Blocked-by: gn0obgx (Implement QueryTasksIntent (JSON parse, optional filters, SwiftData predicate building, JSON array response)), filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters
  - Stream: 3
  - Requirements: [18.2](requirements.md#18.2), [18.3](requirements.md#18.3), [18.5](requirements.md#18.5)

## End-to-End Testing

- [ ] 49. Write UI tests (navigation flows, sheet presentation, empty states, filter badge, abandoned opacity, default segment) <!-- id:gn0obgz -->
  - Blocked-by: gn0obgo (Wire navigation (NavigationStack, sheet presentations for AddTask/Detail, popover for filter, push for Settings)), popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover
  - Stream: 2
  - Requirements: [6.4](requirements.md#6.4), [9.1](requirements.md#9.1), [9.3](requirements.md#9.3), [10.1](requirements.md#10.1), [10.7](requirements.md#10.7), [12.1](requirements.md#12.1), [12.2](requirements.md#12.2), [13.3](requirements.md#13.3), [20.1](requirements.md#20.1), [20.2](requirements.md#20.2), [20.4](requirements.md#20.4)

- [ ] 50. Write integration tests (intent creates task visible on dashboard, intent status update reflected, query returns filtered results, display ID counter increments across creates) <!-- id:gn0obh0 -->
  - Blocked-by: gn0obgt (Implement CreateTaskIntent (JSON parse, project resolution, validation, task creation, openAppWhenRun, @MainActor perform)), project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, project, gn0obgv (Implement UpdateStatusIntent (JSON parse, task lookup by displayId, status validation, transition via TaskService)), gn0obgx (Implement QueryTasksIntent (JSON parse, optional filters, SwiftData predicate building, JSON array response)), filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, filters, gn0obgo (Wire navigation (NavigationStack, sheet presentations for AddTask/Detail, popover for filter, push for Settings)), popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover, popover
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [16.1](requirements.md#16.1), [17.1](requirements.md#17.1), [18.1](requirements.md#18.1)
