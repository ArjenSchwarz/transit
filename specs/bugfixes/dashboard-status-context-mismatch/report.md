# Bugfix Report: Dashboard Status Context Mismatch

**Date:** 2026-02-20
**Status:** Fixed
**Ticket:** T-173

## Description of the Issue

Status updates from the dashboard (drag-and-drop) and detail views (TaskEditView, TaskDetailView) may not persist to disk. The in-memory state appears correct because the task object is mutated directly, but the save operation targets a different ModelContext that has no pending changes.

**Reproduction steps:**
1. Launch the app and create a task in Idea status
2. Drag the task to a different column (e.g., In Progress) on the dashboard
3. Force-quit and relaunch the app
4. Observe the task has reverted to its previous status

**Impact:** All status changes made through the UI could silently fail to persist. Task creation via TaskService is also affected since it inserts into the wrong context.

## Investigation Summary

- **Symptoms examined:** Status changes appear to work in-memory but may not survive app restarts
- **Code inspected:** `TransitApp.swift` (init and ScenePhaseModifier), `TaskService.swift`, `DashboardView.swift`, `TaskEditView.swift`, `TaskDetailView.swift`, `CommentService.swift`
- **Hypotheses tested:** Confirmed that `ModelContext(container)` creates an independent context separate from `container.mainContext`, and that `@Query` uses `container.mainContext`

## Discovered Root Cause

In `TransitApp.init()`, line 45 created a **separate** `ModelContext` via `ModelContext(container)`. This context was passed to all services (TaskService, ProjectService, CommentService). However, views use `container.mainContext` through `@Query` and `@Environment(\.modelContext)` (set by `.modelContainer(container)` on the scene).

When a view called `taskService.updateStatus(task:to:)`:
1. The `task` object belongs to `mainContext` (fetched by `@Query`)
2. `StatusEngine.applyTransition` mutates the task -- these mutations happen on `mainContext`
3. `TaskService` calls `self.modelContext.save()` on its **separate** context
4. The separate context has no pending changes, so nothing is written to disk
5. `mainContext` has unsaved changes that are never explicitly saved

**Defect type:** Context mismatch -- two independent ModelContexts used where one was intended

**Why it occurred:** `ModelContext(container)` was used instead of `container.mainContext`, likely because the distinction between the two was not obvious. `ModelContext(container)` creates a fully independent context with its own change tracking.

**Contributing factors:** CommentService had already worked around this issue with a `resolveTask()` method that re-fetches tasks in its own context, which may have masked the broader problem. The `ScenePhaseModifier` also created yet another separate context via `ModelContext(container)`.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/TransitApp.swift:45` - Changed `ModelContext(container)` to `container.mainContext` for service initialization
- `Transit/Transit/TransitApp.swift:102` - Changed `ModelContext(container)` to `container.mainContext` for ScenePhaseModifier

**Approach rationale:** Using `container.mainContext` ensures all services operate on the same context that `@Query` and `@Environment(\.modelContext)` use. This eliminates the cross-context mutation problem entirely. CommentService's existing `resolveTask()` workaround becomes redundant but harmless.

**Alternatives considered:**
- **Re-fetch tasks in TaskService (like CommentService's resolveTask)** - Would work for `updateStatus` but adds complexity to every method that accepts a model object. Doesn't fix the fundamental design issue.
- **Save the task's own context instead of the service's context** - Fragile; relies on `task.modelContext` being set and correct. Doesn't solve the problem for task creation where the service inserts into its own context.

## Regression Test

**Test file:** `Transit/TransitTests/TaskServiceTests.swift`
**Test name:** `updateStatusPersistsWhenUsingSharedContext`

**What it verifies:** When TaskService uses the container's mainContext, status updates on tasks from that context are properly saved and visible when re-fetched from a fresh context on the same container.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/TransitApp.swift` | Use `container.mainContext` instead of `ModelContext(container)` (2 locations) |
| `Transit/TransitTests/TaskServiceTests.swift` | Added regression test for context persistence |
| `Transit/TransitTests/ProjectServiceTests.swift` | Fixed pre-existing `#Predicate` compilation error (unrelated) |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (392 tests, 0 failures)
- [x] Linters pass (0 violations)

## Prevention

**Recommendations to avoid similar bugs:**
- Never use `ModelContext(container)` when the intent is to share a context with SwiftUI views. Always use `container.mainContext`.
- When a service accepts model objects from external callers, ensure the service operates on the same context those objects belong to.
- Add a comment in `TransitApp.init()` explaining why `container.mainContext` is used (context shared with `@Query`).

## Related

- T-173: Status updates from dashboard may not persist due to TaskService context mismatch
- CommentService's `resolveTask()` was a partial workaround for this same class of issue
