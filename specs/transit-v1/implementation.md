# Implementation Explanation: Transit V1

This document explains the Transit V1 implementation across three expertise levels, serving as both documentation and a validation mechanism against the spec.

---

## Beginner Level

### What Was Built

Transit is a task tracker app for Apple devices (iPhone, iPad, Mac). Think of it like a personal kanban board — the kind you might see on a wall with sticky notes arranged in columns like "To Do", "In Progress", and "Done".

The app lets you:
- Create **projects** (groups of related work, each with a name and color)
- Create **tasks** within projects, each with a type (bug, feature, chore, research, documentation)
- Move tasks through stages by dragging them between columns on a board
- Use Siri Shortcuts or the command line to create/update/query tasks programmatically
- Sync everything across your Apple devices via iCloud

### How It's Organized

The app has four layers, like floors of a building:

1. **Models** (basement) — Define what a Project and Task look like (their fields, relationships)
2. **Services** (ground floor) — Business rules: "when a task is marked Done, record the completion time"
3. **Views** (upper floors) — What you see on screen: the kanban board, task cards, settings
4. **Intents** (side entrance) — An alternative way in: Siri Shortcuts and CLI commands that talk to the same services

### Why It Matters

Transit integrates into a developer workflow where AI agents and CI pipelines can update task status programmatically. A CI pipeline could move a task to "Ready for Review" when tests pass. An AI agent could create tasks from a specification. The app is the visual dashboard for tracking all of this.

### Key Concepts

- **Kanban board**: A board with columns representing stages of work. Tasks move left-to-right as they progress.
- **CloudKit**: Apple's cloud database that syncs data between devices automatically.
- **App Intents**: A framework that lets external tools (Shortcuts, CLI) call functions inside the app.
- **Display ID**: A human-friendly number like T-42 (as opposed to the internal UUID).
- **Provisional ID**: When you're offline, tasks get a temporary "T-bullet" ID that upgrades to a real number when you reconnect.

---

## Intermediate Level

### Changes Overview

9 commits implementing the complete Transit V1 from scratch: spec documents, Xcode project setup, data models, domain services, dashboard UI, detail/settings views, App Intents, and test suites. 75 files added, ~8,100 lines of new code.

**Key files by layer:**

| Layer | Files | Purpose |
|-------|-------|---------|
| Models | `Project.swift`, `TransitTask.swift`, `TaskStatus.swift`, `TaskType.swift`, `DisplayID.swift` | SwiftData `@Model` classes with CloudKit-compatible fields |
| Services | `StatusEngine.swift`, `TaskService.swift`, `ProjectService.swift`, `DisplayIDAllocator.swift` | Business logic, status transitions, display ID allocation |
| Views | `DashboardView.swift`, `ColumnView.swift`, `TaskCardView.swift`, `TaskDetailView.swift`, `TaskEditView.swift`, `AddTaskSheet.swift`, `SettingsView.swift`, `ProjectEditView.swift` | SwiftUI views with adaptive layout |
| Intents | `CreateTaskIntent.swift`, `UpdateStatusIntent.swift`, `QueryTasksIntent.swift`, `IntentError.swift`, `IntentHelpers.swift` | App Intents with JSON I/O |
| Infrastructure | `TransitApp.swift`, `SyncManager.swift`, `ConnectivityMonitor.swift` | App entry point, CloudKit sync toggle, network monitoring |

### Implementation Approach

**Data Model**: SwiftData `@Model` classes with raw-value storage for enums (CloudKit requires primitive types). Relationships are optional because CloudKit doesn't guarantee record delivery order. Metadata is stored as a JSON string since CloudKit doesn't support dictionary fields.

**Status Engine Pattern**: All status transitions go through `StatusEngine.applyTransition()`, which handles side effects (setting/clearing `completionDate`, updating `lastStatusChangeDate`). This is the single source of truth — UI drag-and-drop, detail view edits, and App Intents all use the same path via `TaskService`.

**Adaptive Dashboard Layout**: `DashboardView` uses `GeometryReader` to calculate how many columns fit. iPhone portrait gets a segmented control (1 column), landscape gets 3 columns with paging, iPad/Mac gets up to 5. The static `buildFilteredColumns()` method handles column grouping, 48-hour terminal cutoff, and sorting (handoff tasks first, then by date).

**Display ID Allocation**: Uses a CloudKit counter record with `CKModifyRecordsOperation` and `.ifServerRecordUnchanged` save policy for optimistic locking. Falls back to provisional IDs offline. Promotion triggers on app launch, foreground, and network restore via `NWPathMonitor`.

**App Intents**: Each intent has a static `execute()` method that takes services as parameters, making the logic testable without `@Dependency` injection. All intents set `openAppWhenRun = true` to ensure in-process execution with access to the shared `ModelContainer`.

**Test Strategy**: 245+ tests across unit tests (Swift Testing framework), integration tests, and UI tests (XCTest). Unit tests cover StatusEngine, services, intent logic, dashboard filtering/sorting. Integration tests verify the intent-to-dashboard pipeline. UI tests cover navigation flows and empty states.

### Trade-offs

- **SwiftData + direct CloudKit** (hybrid data layer): SwiftData handles model persistence and automatic sync. Direct CloudKit API is only used for the display ID counter where optimistic locking is required. This avoids reimplementing CRUD and sync for models while keeping precise control over the counter.

- **Domain services over MVVM**: SwiftData's `@Query` already provides reactive data binding. Adding view models would duplicate query logic. Services centralise mutations so the same rules apply from all entry points.

- **`openAppWhenRun = true`**: Avoids App Group container complexity. The trade-off is the app briefly foregrounds when intents run from CLI, which is acceptable for a developer tool.

- **Sync toggle via UserDefaults**: The `ModelContainer` is configured at startup based on the `syncEnabled` preference. Changing the toggle takes effect on next launch. Runtime toggling would require recreating the container and tearing down the view hierarchy.

---

## Expert Level

### Technical Deep Dive

**Swift 6 Actor Isolation**: The project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, meaning all types default to `@MainActor`. Types that need to work across actor boundaries (e.g., `IntentError`, `IntentHelpers`, `DisplayID`) are explicitly marked `nonisolated`. `DisplayIDAllocator` uses `@unchecked Sendable` because `CKContainer` and `CKDatabase` are safe to use across actors but don't conform to `Sendable`. App Intent `perform()` methods are marked `@MainActor` to access `@MainActor`-isolated services.

**CloudKit Counter Record Placement**: The counter record lives in `com.apple.coredata.cloudkit.zone` — the same zone SwiftData uses. This is intentional: it means the counter syncs via the same subscription as model records, avoiding a separate zone subscription.

**Display ID Allocation Edge Cases**:
- First-ever allocation creates the counter with `nextDisplayId = 2` (returning 1).
- Race condition between two devices both creating the counter: one gets `serverRecordChanged`, fetches the server's version, and continues normally.
- Partial promotion: if promoting 3 provisional tasks and the 2nd fails, the 1st keeps its permanent ID and the 2nd/3rd retry next time. Gaps in display IDs are acceptable per spec.

**Dashboard Column Filtering**: The `buildFilteredColumns` static method is extracted for testability. Key details:
- Terminal tasks with nil `completionDate` are treated as just-completed (defensive — prevents data loss from silent filtering).
- Sorting: done before abandoned within the terminal column, handoff before regular within each column, then by `lastStatusChangeDate` descending.
- All columns are always present in the dictionary (even if empty) to prevent UI glitches.

**Drag-and-Drop**: Uses SwiftUI's `.draggable(task.id.uuidString)` and `.dropDestination(for: String.self)`. The UUID string round-trips through the pasteboard. Each column's drop handler maps to `column.primaryStatus`, which assigns the base status (never handoff or abandoned via drag).

**Intent JSON Pattern**: Intents use `JSONSerialization` rather than `Codable` because the input schema is flexible (optional fields, type coercion). The static `execute()` pattern allows tests to call intent logic directly without wiring up `@Dependency` and `AppDependencyManager`.

**ModelContext Sharing**: `TransitApp` creates a single `ModelContext` shared between `TaskService` and `ProjectService`. The `ScenePhaseModifier` creates its own `ModelContext` from the same container for display ID promotion, which runs asynchronously and needs isolation.

### Architecture Impact

- **Single mutation path** via services means future entry points (MCP agent, widgets) can add task operations without risk of inconsistent status handling.
- **CloudKit counter** in the SwiftData zone means the display ID system is coupled to CloudKit sync — if CloudKit is disabled, provisional IDs accumulate until sync is re-enabled.
- **No schema versioning** means V2 schema changes will need a migration strategy designed from scratch.

### Potential Issues

1. **Sync toggle latency**: The CloudKit configuration is set at `ModelContainer` creation. Disabling sync takes effect on next launch, not immediately. Users may be confused if they toggle sync off and see one more sync occur.

2. **Display ID allocation under load**: The optimistic locking retry loop (5 attempts) could fail if many devices allocate simultaneously. In practice, this is a single-user app, so contention is near-zero.

3. **ModelContext thread safety**: The shared `ModelContext` between `TaskService` and `ProjectService` is safe because both are `@MainActor`. However, `promoteProvisionalTasks` accesses a separate `ModelContext` from an async context — this works because `ModelContext` is not `Sendable` but the access is `@MainActor`-isolated via the calling scope.

4. **48-hour cutoff uses device-local time**: If the device clock is wrong, tasks may appear or disappear from the Done/Abandoned column unexpectedly. This is per spec and acceptable for a single-user app.

---

## Completeness Assessment

### Fully Implemented

All 20 requirement sections (1-20) from the spec are implemented:
- Data models with CloudKit-compatible fields and optional relationships
- 8 task statuses with column mapping, handoff detection, terminal detection
- Display ID allocation with CloudKit counter, provisional IDs, and promotion
- 5-column kanban dashboard with adaptive layout (portrait/landscape/iPad/Mac)
- Task cards with glass effect, project color border, abandoned styling
- Drag-and-drop between all columns with correct status mapping
- Navigation bar with grouped toolbar buttons
- Project filter with multi-select and badge count
- Add task sheet with project picker, validation, platform-adaptive presentation
- Task detail view (read-only) with abandon/restore actions
- Task edit view with all editable fields including status picker and metadata
- Settings view with project list, active counts, sync toggle, about section
- Project create/edit with color picker
- Liquid Glass materials on task cards
- CloudKit sync with private database
- Three App Intents (Create, Update Status, Query) with JSON I/O
- Structured error responses with all 6 error codes
- Empty states for dashboard, columns, settings, and no-project add task

### Requirement Traceability

| Req | Description | Implementation |
|-----|-------------|---------------|
| 1.1-1.6 | Project data model | `Project.swift`, `ProjectService.swift`, `ProjectEditView.swift` |
| 2.1-2.7 | Task data model | `TransitTask.swift`, `TaskService.swift` |
| 3.1-3.8 | Display ID allocation | `DisplayIDAllocator.swift`, `DisplayID.swift` |
| 4.1-4.8 | Status progression | `StatusEngine.swift`, `TaskStatus.swift` |
| 5.1-5.9 | Dashboard kanban | `DashboardView.swift`, `ColumnView.swift` |
| 6.1-6.4 | Task cards | `TaskCardView.swift` |
| 7.1-7.5 | Drag and drop | `DashboardView.handleDrop()`, `DashboardColumn.primaryStatus` |
| 8.1-8.3 | Navigation bar | `DashboardView.toolbar` |
| 9.1-9.6 | Project filter | `FilterPopoverView.swift`, `DashboardView.selectedProjectIDs` |
| 10.1-10.7 | Add task | `AddTaskSheet.swift` |
| 11.1-11.9 | Detail view | `TaskDetailView.swift`, `TaskEditView.swift` |
| 12.1-12.9 | Settings | `SettingsView.swift`, `SyncManager.swift` |
| 13.1-13.7 | Adaptive layout | `DashboardView` GeometryReader logic |
| 14.1-14.5 | Liquid Glass | `.glassEffect()` in `TaskCardView.swift` |
| 15.1-15.6 | CloudKit sync | `SyncManager.swift`, `TransitApp.swift` |
| 16.1-16.8 | Create Task intent | `CreateTaskIntent.swift` |
| 17.1-17.6 | Update Status intent | `UpdateStatusIntent.swift` |
| 18.1-18.5 | Query Tasks intent | `QueryTasksIntent.swift` |
| 19.1-19.3 | Intent error handling | `IntentError.swift` |
| 20.1-20.4 | Empty states | `EmptyStateView.swift`, conditional rendering |

### Known Limitations (by design)

- Sync toggle takes effect on next app launch (Decision 19)
- No task deletion — tasks can only be abandoned (req 2.7)
- No project deletion in V1 (req 1.6)
- Filter state is ephemeral, resets on launch (req 9.6)
- Display IDs may have gaps due to sync conflicts (req 3.3)

### Test Coverage

- 245+ tests across unit, integration, and UI test suites
- Core business logic (StatusEngine, services, intents) well-covered
- Dashboard filtering and sorting logic tested via static method extraction
- Integration tests verify intent-to-dashboard pipeline
- UI tests cover navigation flows, empty states, and default selections
