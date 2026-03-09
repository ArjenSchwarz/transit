# Bugfix Report: Non-Atomic TaskEditView Saves

**Date:** 2026-03-09
**Status:** Fixed

## Description of the Issue

`TaskEditView.save()` performed three sequential save operations: `changeProject()`, `setMilestone()`, and `updateStatus()` / `modelContext.save()`. If a later step failed, earlier steps had already persisted their changes. The user would see "Could not save task" but the task would be partially updated (e.g., project changed but status not).

**Reproduction steps:**
1. Open a task for editing
2. Change the project, milestone, and status simultaneously
3. If the status change or final save fails, the project and milestone changes are already persisted
4. The rollback only reverts unpersisted in-memory changes

**Impact:** Data integrity issue. Users could end up with tasks in inconsistent states where some edits were saved and others were not, despite seeing an error message suggesting nothing was saved.

## Investigation Summary

- **Symptoms examined:** `TaskEditView.save()` calls three service methods that each call `modelContext.save()` independently
- **Code inspected:** `TaskEditView.swift`, `TaskService.swift`, `MilestoneService.swift`
- **Hypotheses tested:** Confirmed that `changeProject` and `setMilestone` each save independently, making the overall operation non-atomic

## Discovered Root Cause

Each service method (`changeProject`, `setMilestone`, `updateStatus`) calls `modelContext.save()` internally. When called in sequence from `TaskEditView.save()`, the first two persist their changes before the third runs. If the third fails, `rollback()` only reverts the third operation's in-memory changes — the first two are already on disk.

**Defect type:** Non-atomic composite operation

**Why it occurred:** The service methods were designed for standalone use where each should persist independently. When composed in `TaskEditView.save()`, the individual saves created a non-atomic sequence.

**Contributing factors:** The `save: false` pattern already existed in `CommentService.addComment()` (used by `updateStatus` for atomic comment+status saves), but wasn't applied to `changeProject` or `setMilestone`.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/TaskService.swift` — Added `save: Bool = true` parameter to `changeProject()` and `updateStatus()`. When `save: false`, the method performs in-memory mutations and validation but skips `modelContext.save()`.
- `Transit/Transit/Services/MilestoneService.swift` — Added `save: Bool = true` parameter to `setMilestone()`. Same pattern.
- `Transit/Transit/Views/TaskDetail/TaskEditView.swift` — Updated `save()` to pass `save: false` to all three service calls, then perform a single `modelContext.save()` at the end. On failure, `rollback()` reverts all changes atomically.

**Approach rationale:** Follows the established `save: Bool = true` pattern from `CommentService.addComment()`. Default parameter value preserves backward compatibility — all existing callers continue to save immediately.

**Alternatives considered:**
- Wrapping in a child `ModelContext` for transaction isolation — SwiftData doesn't support nested contexts, so this isn't viable.
- Creating a dedicated `TaskService.updateTask(...)` method that takes all fields — would duplicate view logic and create a rigid API that must change whenever fields are added.

## Regression Test

**Test file:** `Transit/TransitTests/TaskEditSaveErrorTests.swift`
**Test names:**
- `changeProjectWithSaveFalseDoesNotPersist` — verifies `save: false` defers persistence on project change
- `setMilestoneWithSaveFalseDoesNotPersist` — verifies `save: false` defers persistence on milestone assignment
- `updateStatusWithSaveFalseDoesNotPersist` — verifies `save: false` defers persistence on status change
- `atomicSaveCommitsAllDeferredChanges` — simulates the full `TaskEditView.save()` pattern with deferred saves and a single atomic commit

**What it verifies:** That deferred service calls don't persist until an explicit `modelContext.save()`, and that all changes can be committed or rolled back as a unit.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/TaskService.swift` | Added `save: Bool = true` to `changeProject()` and `updateStatus()` |
| `Transit/Transit/Services/MilestoneService.swift` | Added `save: Bool = true` to `setMilestone()` |
| `Transit/Transit/Views/TaskDetail/TaskEditView.swift` | Use `save: false` for all service calls, single `modelContext.save()` at end |
| `Transit/TransitTests/TaskEditSaveErrorTests.swift` | Added four regression tests for atomic save behaviour |

## Verification

**Automated:**
- [x] Regression tests pass
- [x] Full test suite passes (`make test-quick`)
- [x] Linters pass (`make lint`)

## Prevention

**Recommendations to avoid similar bugs:**
- When composing multiple service calls in a view's save action, always use `save: false` and perform a single `modelContext.save()` at the caller level
- Service methods that mutate and persist should consistently offer the `save: Bool = true` parameter for composition

## Related

- T-148: Task edits ignore save failures (original error handling fix)
- T-317: Rollback promotion state on save failure (similar rollback pattern)
