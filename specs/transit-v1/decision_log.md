# Decision Log: Transit V1

## Decision 1: Feature Name

**Date**: 2026-02-09
**Status**: accepted

### Context

Need to establish the spec directory name and feature identifier for the V1 implementation of Transit.

### Decision

Use `transit-v1` as the feature name and `specs/transit-v1/` as the spec directory.

### Rationale

Matches the scope — this covers the complete V1 of the Transit app. Simple and descriptive.

### Alternatives Considered

- **transit-app-v1**: More explicit but unnecessarily verbose given there's no ambiguity in this repository.

### Consequences

**Positive:**
- Clear, concise naming
- Consistent with the design doc which uses "V1" terminology throughout

**Negative:**
- None identified

---

## Decision 2: No Data Migration in V1

**Date**: 2026-02-09
**Status**: accepted

### Context

As a greenfield project with no existing users or data, the question is whether V1 needs to account for future data migration or schema versioning.

### Decision

No data migration or schema versioning provisions in V1. CloudKit schema is created fresh.

### Rationale

There are no existing users or data to migrate. Adding schema versioning now would be speculative complexity. CloudKit's schema management allows additive changes without breaking existing records.

### Alternatives Considered

- **Include basic schema versioning**: Would future-proof the data layer but adds implementation complexity for a scenario that may never require it.

### Consequences

**Positive:**
- Simpler implementation
- No speculative abstractions

**Negative:**
- If V2 requires schema changes, migration strategy will need to be designed then

---

## Decision 3: Minimal-Functional Detail View

**Date**: 2026-02-09
**Status**: accepted

### Context

The design doc states the detail view "will be iterated on across versions" and "V1 should be functional but doesn't need to be heavily designed."

### Decision

Detail view is minimal-functional: display all fields, basic edit mode, Abandon/Restore actions. No visual polish beyond functional presentation.

### Rationale

Aligns with the design doc's explicit guidance. Investing in detail view polish now risks rework when the view is iterated on in future versions.

### Alternatives Considered

- **Moderately polished**: Add glass materials and proper layout. Rejected as premature given the design doc's guidance.

### Consequences

**Positive:**
- Faster implementation
- Avoids rework when V2 iterates on the view

**Negative:**
- Detail view will look basic compared to the dashboard

---

## Decision 4: Offline Task Creation Required

**Date**: 2026-02-09
**Status**: accepted

### Context

The design doc describes provisional local IDs for tasks created offline, with permanent display IDs assigned on first sync. The question is whether V1 needs this or can require network connectivity.

### Decision

V1 must support offline task creation with provisional local IDs as described in the design doc.

### Rationale

A task tracker that can't capture ideas when offline (e.g., on a plane, in poor reception areas) fails its core purpose. The design doc explicitly describes this behavior.

### Alternatives Considered

- **Online-only for V1**: Simpler implementation but undermines the core use case of quick task capture.

### Consequences

**Positive:**
- App works reliably regardless of connectivity
- Matches the design doc's specification

**Negative:**
- More complex display ID allocation logic (provisional → permanent)
- Need to handle sync edge cases for offline-created tasks

---

## Decision 5: Task Description is Optional

**Date**: 2026-02-09
**Status**: accepted

### Context

The design doc's data model table marks description as required, but the Add Task UI section says "multiline text field, optional." The data model, UI, and intents need to agree.

### Decision

Description is optional everywhere — data model, UI, and intents. An empty or nil value is permitted.

### Rationale

Task capture should be fast and friction-free. Requiring a description for every quick idea slows down the most common interaction. The design doc's UI section already treats it as optional.

### Alternatives Considered

- **Required everywhere**: Ensures tasks have context but adds friction for quick capture. Rejected because it conflicts with the "capture first, promote later" philosophy.

### Consequences

**Positive:**
- Faster task creation
- Consistent behavior across UI and intents

**Negative:**
- Some tasks may lack descriptions, reducing dashboard usefulness

---

## Decision 6: Bidirectional Drag Between All Columns

**Date**: 2026-02-09
**Status**: accepted

### Context

The design doc says tasks can be dragged between columns but doesn't specify whether backward transitions (e.g., In Progress → Planning) are allowed. Done and Abandoned tasks appear in the final column — it's unclear if they can be dragged out.

### Decision

Forward and backward drag is allowed between all columns. Done and Abandoned tasks can be dragged back to any column, which clears their `completionDate` and sets the new status.

### Rationale

Single-user app — restricting drag direction adds complexity without protecting against multi-user misuse. Users should be able to reclassify work freely. Restoring via detail view is still available but drag provides a faster path.

### Alternatives Considered

- **Forward only, restore via detail**: Restricts drag to forward-only. Rejected as unnecessarily restrictive for a single-user tool.
- **Free for active, detail for terminal**: Active tasks move freely, terminal tasks only via detail view. Rejected as an inconsistent interaction model.

### Consequences

**Positive:**
- Simple, consistent interaction model
- Fast reclassification of work

**Negative:**
- Accidental drags could change status unexpectedly (mitigated by single-user context)
- Dragging a Done task back clears its completion date

---

## Decision 7: Create Task Intent Always Creates in Idea Status

**Date**: 2026-02-09
**Status**: accepted

### Context

The design doc mentions App Intents "support creating directly into any status" for CLI mid-sprint use. The requirements need to decide whether the Create Task intent accepts an optional status parameter.

### Decision

The Create Task intent always creates tasks in Idea status. No status parameter is accepted.

### Rationale

Keeps the intent simple and consistent with the UI. If a CLI user needs a task in a different status, they can create it and immediately update the status via the Update Status intent. This avoids duplicating status validation logic in the creation intent.

### Alternatives Considered

- **Optional status parameter**: More flexible for CLI workflows. Rejected to keep V1 simple; the two-step create-then-update workflow covers the use case.

### Consequences

**Positive:**
- Simpler intent interface
- Consistent with UI behavior

**Negative:**
- CLI workflows require two commands to create a task in non-Idea status

---

## Decision 8: Done Tasks Can Be Abandoned, Status Picker in Detail View

**Date**: 2026-02-09
**Status**: accepted

### Context

Two related questions: (1) Can Done tasks be abandoned? (2) Is status directly editable in the detail view, or only changeable via drag and Abandon/Restore?

### Decision

Done tasks can be abandoned (from any status, including Done). The detail view includes a status picker in edit mode for direct status changes.

### Rationale

Abandoning a Done task handles the "completed prematurely" or "turns out this was wrong" scenario. A status picker in the detail view provides a direct way to change status without needing to find the right column on the dashboard, which is especially useful on iPhone where only one column is visible at a time.

### Alternatives Considered

- **Done cannot be abandoned, no status picker**: Limits flexibility. Rejected because single-user apps should minimize restrictions.
- **Done can be abandoned, no status picker**: Abandon from any status but no general status editing. Rejected because the status picker is valuable on iPhone.

### Consequences

**Positive:**
- Full flexibility for status management
- Better iPhone experience (no need to switch between segmented control and dashboard for status changes)

**Negative:**
- Abandoning a Done task overwrites the original completion date
- Status picker adds UI complexity to the detail view

---

## Decision 9: Block Add Task When No Projects Exist

**Date**: 2026-02-09
**Status**: accepted

### Context

On first launch with zero projects, the user may tap the Add Task button. The creation sheet requires a project picker, so tasks can't be created without at least one project.

### Decision

When no projects exist, tapping Add Task shows a message directing the user to create a project first. The Add Task button is disabled or shows an informational prompt.

### Rationale

Simple and explicit. The user immediately understands what they need to do. Avoids creating hidden default projects or complex inline flows.

### Alternatives Considered

- **Inline project creation**: Let the user create a project from within the Add Task sheet. Rejected as it adds complexity to the creation sheet for a one-time scenario.
- **Default project**: Auto-create an "Inbox" or "Personal" project. Rejected because it creates data the user didn't ask for and may not want.

### Consequences

**Positive:**
- Clear user guidance
- No hidden data creation

**Negative:**
- Adds a small friction point on first launch

---

## Decision 10: Provisional Display IDs Show as "T-bullet"

**Date**: 2026-02-09
**Status**: accepted

### Context

Tasks created offline need a provisional display ID until they sync and receive a permanent one. The visual format of the provisional ID needs to be specified.

### Decision

Provisional display IDs render as "T-•" (T-bullet) with a dimmed/secondary style until a permanent ID is assigned on first sync.

### Rationale

The bullet character signals "pending" without introducing confusing numbering (like negative numbers). Dimmed styling provides additional visual distinction. Once synced, the ID updates to the standard "T-{number}" format.

### Alternatives Considered

- **Negative local numbers (T--1, T--2)**: Visually distinct but confusing — users may think negative IDs are real. Rejected.
- **Hidden until synced**: No ID shown at all. Rejected because users may reference newly created tasks immediately.

### Consequences

**Positive:**
- Clear visual signal that the ID is provisional
- No risk of users referencing a temporary number that later changes

**Negative:**
- Users can't reference the specific task by ID until sync completes

---

## Decision 11: Two Separate Toolbar Button Groups

**Date**: 2026-02-09
**Status**: accepted

### Context

The original requirement grouped all three navigation bar buttons (filter, add, settings) into a single pill container. The settings button serves a different purpose (infrequent navigation) compared to filter and add (frequent dashboard actions).

### Decision

Split into two groups: filter + add in one pill container, settings in a separate pill container.

### Rationale

Groups buttons by function. Filter and add are both task-related dashboard actions. Settings is navigation to a different screen. Separating them visually communicates this distinction and matches iOS 26 conventions where toolbar groups reflect functional grouping.

### Alternatives Considered

- **Single group for all three**: Simpler but treats settings as equivalent to filter/add. Rejected because the visual grouping should reflect functional grouping.

### Consequences

**Positive:**
- Clearer visual hierarchy in the navigation bar
- Follows iOS 26 toolbar grouping conventions

**Negative:**
- None identified

---

## Decision 12: Adaptive Column Count Based on Window Width

**Date**: 2026-02-09
**Status**: accepted

### Context

The original requirement stated iPad and Mac always show all five columns. However, Mac windows can be resized and iPad supports Split View, meaning the available width may be too narrow for five columns.

### Decision

The number of visible columns adapts to the available window width. All five columns show when space permits; fewer columns with horizontal scrolling when narrowed. At minimum width (single-column), fall back to the iPhone portrait layout with a segmented control.

### Rationale

A fixed five-column layout breaks when the window is narrow (Mac resize, iPad Split View at minimum width). Adaptive layout ensures the app remains usable across all window sizes without requiring the user to expand the window.

### Alternatives Considered

- **Fixed five columns always**: Simpler but broken at narrow widths — columns would be too compressed to read. Rejected.
- **Minimum window size enforcement**: Prevents narrow windows entirely. Rejected because it limits multitasking (iPad Split View) unnecessarily.

### Consequences

**Positive:**
- Works correctly in iPad Split View and Mac window resizing
- Seamless transition from multi-column to single-column

**Negative:**
- More complex layout logic with breakpoints
- Need to determine column width thresholds

---

## Decision 13: Hybrid Data Layer — SwiftData + Direct CloudKit

**Date**: 2026-02-09
**Status**: accepted

### Context

The app needs model persistence with CloudKit sync for Project and Task records, plus a display ID counter that requires optimistic locking. SwiftData provides automatic CloudKit sync but doesn't support optimistic locking on arbitrary records.

### Decision

Use SwiftData for Project and Task models (automatic persistence and CloudKit sync). Use direct CloudKit API (`CKDatabase`, `CKModifyRecordsOperation` with `.ifServerRecordUnchanged`) only for the display ID counter record.

### Rationale

SwiftData handles the heavy lifting for models — persistence, queries via `@Query`, and CloudKit sync are all automatic. The counter record is the one case that needs direct CloudKit control for optimistic locking, and it's a single record with simple read-increment-write semantics.

### Alternatives Considered

- **Pure CloudKit (CKRecord everywhere)**: Full control but significant boilerplate for CRUD, queries, change tracking, and sync notifications that SwiftData provides for free. Rejected.
- **Pure SwiftData (counter as a model)**: Simpler but no way to enforce optimistic locking on the counter. Concurrent writes from multiple devices could produce duplicate display IDs. Rejected.

### Consequences

**Positive:**
- Minimal boilerplate for model persistence and sync
- `@Query` provides reactive data binding in views
- Only one component (DisplayIDAllocator) interacts with raw CloudKit

**Negative:**
- Two data access patterns in the same app (SwiftData + direct CloudKit)
- SwiftData's CloudKit integration has constraints: optional relationships, no unique constraints enforcement in CloudKit

---

## Decision 14: Single Multiplatform Target

**Date**: 2026-02-09
**Status**: accepted

### Context

The app targets iOS, iPadOS, and macOS. The question is whether to use a single multiplatform Xcode target or separate per-platform targets.

### Decision

Single multiplatform target supporting iOS, iPadOS, and macOS via SwiftUI's cross-platform capabilities.

### Rationale

SwiftUI provides cross-platform support with minimal platform-specific code. The adaptive layout (GeometryReader-based column count) handles the differences between iPhone, iPad, and Mac. Separate targets would add project complexity without benefit given that the UI is fundamentally the same across platforms.

### Alternatives Considered

- **Separate targets with shared framework**: More control over platform-specific behavior but significantly more project overhead (three targets, a shared framework, build configuration). Rejected as unnecessary for this app.

### Consequences

**Positive:**
- Single build configuration
- Shared code by default, platform branches only where needed
- Simpler CI and testing

**Negative:**
- Platform-specific customisation requires `#if os()` conditionals
- Mac-specific behaviors (window resizing, menu bar) need explicit handling

---

## Decision 15: Domain Services Over View Models

**Date**: 2026-02-09
**Status**: accepted

### Context

SwiftData's `@Query` provides reactive data directly in views. The question is whether to use traditional view models (MVVM) or domain services that encapsulate business logic while letting views query data directly.

### Decision

Use domain services (`TaskService`, `ProjectService`, `StatusEngine`) injected into the environment. Views use `@Query` for reading data and call services for mutations. No per-view view models.

### Rationale

SwiftData's `@Query` already provides the "view model" reactive layer for reads. Adding view models on top would duplicate query logic without benefit. Domain services centralise mutation logic (status transitions, display ID allocation) in one place so that the same rules apply regardless of whether the mutation comes from a view, drag-and-drop, or an App Intent.

### Alternatives Considered

- **MVVM with per-view view models**: Traditional but redundant with `@Query`. View models would just wrap SwiftData queries and forward mutations to services. Rejected as unnecessary indirection.
- **Logic in views**: Simpler but duplicates status transition rules across dashboard drag-and-drop, detail view status picker, and App Intents. Rejected.

### Consequences

**Positive:**
- Single source of truth for business rules
- App Intents and views share the same mutation path
- Views stay declarative (read via @Query, write via services)

**Negative:**
- Services need to be environment-injected, adding setup in the app entry point

---

## Decision 16: Optional Relationships for CloudKit Compatibility

**Date**: 2026-02-09
**Status**: accepted

### Context

Design review identified that `var project: Project` (non-optional) and `var tasks: [TransitTask]` (non-optional) on the SwiftData models are incompatible with CloudKit. CloudKit does not guarantee record delivery order — a Task can sync before its parent Project, resulting in a nil relationship at the Core Data level. Non-optional Swift types would crash in this scenario.

### Decision

Make both relationships optional: `var project: Project?` on TransitTask and `var tasks: [TransitTask]?` on Project. The "every task belongs to a project" invariant is enforced in the service layer (`TaskService.createTask` requires a non-nil Project parameter), not in the data model.

### Rationale

CloudKit compatibility is non-negotiable. The model must tolerate transient nil states during sync. Service-layer enforcement provides the same guarantee for application code while allowing the persistence layer to handle CloudKit's eventual consistency.

### Alternatives Considered

- **Keep non-optional and hope SwiftData handles it**: Incorrect — SwiftData does not silently resolve non-optional relationships when CloudKit delivers records out of order. Would crash at runtime.

### Consequences

**Positive:**
- Correct CloudKit behavior under all sync scenarios
- Explicit nil handling surfaces edge cases at compile time

**Negative:**
- Every access to `task.project` and `project.tasks` requires nil handling
- `#Predicate` cannot traverse optional to-many relationships — must query from child side or filter in-memory

---

## Decision 17: Add creationDate Field to TransitTask

**Date**: 2026-02-09
**Status**: accepted

### Context

The `promoteProvisionalTasks` method sorted provisional tasks by `lastStatusChangeDate` to determine display ID assignment order. But `lastStatusChangeDate` updates on every status transition — a task created first but moved to Planning would sort after a task created later that stayed in Idea.

### Decision

Add `var creationDate: Date` to TransitTask, set once at creation, never modified. Use this for provisional task promotion sorting.

### Rationale

Display IDs should reflect creation order (within a single device), not the most recent status change. `creationDate` is also useful for future features like creation timestamps in history views.

### Alternatives Considered

- **Keep sorting by lastStatusChangeDate**: Simpler but produces non-intuitive ID ordering where a task created first gets a higher ID because it was moved sooner.

### Consequences

**Positive:**
- Display IDs on a single device reflect creation order
- Useful metadata for future features

**Negative:**
- One additional field on every task record

---

## Decision 18: openAppWhenRun for App Intents

**Date**: 2026-02-09
**Status**: accepted

### Context

App Intents invoked from Shortcuts or CLI (`shortcuts run`) may execute in an extension process, not the app's main process. The shared `ModelContainer` and `@MainActor` services would not be available in an out-of-process context.

### Decision

All intents set `openAppWhenRun = true` to ensure in-process execution. The app briefly opens when an intent runs from Shortcuts or CLI.

### Rationale

The alternative (App Group containers) adds significant complexity: a shared container configuration, careful coordination between app and extension processes, and potential Core Data concurrency issues. `openAppWhenRun = true` is simple, correct, and already a requirement for future MCP integration (the app must be running).

### Alternatives Considered

- **App Group container**: Configure SwiftData to use a shared App Group so an extension process can access the same store. More complex, introduces cross-process coordination issues, and not needed given that the app being open is already a requirement for MCP.

### Consequences

**Positive:**
- Simple, correct, no cross-process issues
- Consistent with MCP requirement (app must be running)

**Negative:**
- App briefly foregrounds when CLI commands are run (acceptable for a developer-facing tool)

---

## Decision 19: Pragmatic Sync Toggle via CloudKit Options

**Date**: 2026-02-09
**Status**: accepted

### Context

Requirement [12.7] specifies a toggle to enable/disable CloudKit sync. Toggling CloudKit at runtime is non-trivial — you cannot reconfigure a live `ModelContainer`.

### Decision

The `ModelContainer` is always created with CloudKit enabled. The sync toggle controls `NSPersistentStoreDescription.cloudKitContainerOptions`: set to nil to pause sync, restore to re-enable. On re-enable, persistent history tracking handles the delta sync of changes made while sync was off.

### Rationale

This avoids recreating the `ModelContainer` (which requires tearing down and recreating the entire view hierarchy). Toggling `cloudKitContainerOptions` is the least disruptive approach that still provides real sync control.

### Alternatives Considered

- **Recreate ModelContainer**: Tear down views, create new container with different config, re-inject. Simpler to reason about but highly disruptive to the user experience.
- **Informational toggle only**: Show sync status without actual control. Rejected because the requirement explicitly calls for enable/disable.

### Consequences

**Positive:**
- No view hierarchy disruption
- Real sync control (not just informational)

**Negative:**
- Relies on `NSPersistentStoreDescription` API that is Core Data-level, not SwiftData-level
- Needs careful testing to verify delta sync works correctly on re-enable

---

## Decision 20: Drag to Column Assigns Base Status

**Date**: 2026-02-09
**Status**: accepted

### Context

Each dashboard column can contain multiple statuses (e.g., Spec column contains both `spec` and `readyForImplementation`). When a task is dragged to a column, the system needs to decide which status to assign.

### Decision

Dragging to a column always assigns the "base" status: Spec (not readyForImplementation), In Progress (not readyForReview), Done (not Abandoned). Handoff statuses (readyForImplementation, readyForReview) are only set via the detail view status picker or App Intents.

### Rationale

Handoff statuses are intentional signals ("this needs human attention") that should be set deliberately, not accidentally via a drag. The base status is always the safe default. This also simplifies drag-and-drop — no disambiguation UI needed.

### Alternatives Considered

- **Show a picker on drop**: Let the user choose between sub-statuses when dropping on a multi-status column. Rejected as it adds friction to the most common interaction (quick status change).

### Consequences

**Positive:**
- Drag-and-drop is always a single, predictable action
- Handoff statuses require explicit intent

**Negative:**
- Users cannot set handoff statuses via drag (must use detail view or CLI)
