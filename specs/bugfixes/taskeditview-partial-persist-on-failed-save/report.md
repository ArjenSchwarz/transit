# Bugfix Report: TaskEditView Partial Persist on Failed Save

**Date:** 2026-03-09
**Status:** Fixed

## Description of the Issue

When editing a task in `TaskEditView`, the `save()` method mutated task properties (name, description, type, metadata) directly on the model object **before** entering the `do` block. Service calls within the `do` block (`changeProject`, `setMilestone`) each call `modelContext.save()` internally, which persisted those direct mutations as a side effect. If a later step (e.g., `updateStatus`) then failed, the `rollback()` in the `catch` block could not revert the already-saved property changes.

**Reproduction steps:**
1. Open a task and tap Edit
2. Change the name, type, and status simultaneously
3. Trigger a save failure on the status update (e.g., via a sync conflict)
4. Observe: the name and type changes are persisted, but the status change is rolled back

**Impact:** Data inconsistency -- partial edits persisted despite a failed save. The user sees an error alert but some of their changes are already saved, with no way to know which ones.

## Investigation Summary

- **Symptoms examined:** `TaskEditView.save()` applies direct property mutations (lines 283-288) before the `do` block, then calls service methods that internally save the model context.
- **Code inspected:** `TaskEditView.swift`, `TaskService.changeProject()`, `MilestoneService.setMilestone()`, `TaskService.updateStatus()`
- **Hypotheses tested:** Confirmed that `modelContext.save()` inside service methods persists all pending mutations on that context, not just the ones the service method applied.

## Discovered Root Cause

The `save()` method applied direct property mutations (`task.name`, `task.taskDescription`, `task.type`, `task.metadata`) **outside** and **before** the `do/catch` block. When `changeProject()` or `setMilestone()` called `modelContext.save()` internally, those pending direct mutations were persisted as a side effect. If a subsequent step failed, `rollback()` could not revert the already-committed changes.

**Defect type:** Incorrect mutation ordering leading to partial persistence

**Why it occurred:** The T-148 fix correctly added `do/catch` and `rollback()`, but placed the direct mutations before the `do` block. The interaction between direct mutations and intermediate service saves was not considered.

**Contributing factors:** Service methods (`changeProject`, `setMilestone`) call `modelContext.save()` internally, which flushes all pending mutations on the shared context -- not just the ones the service method applied.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/TaskDetail/TaskEditView.swift` -- Moved direct property mutations (`task.name`, `task.taskDescription`, `task.type`, `task.metadata`) inside the `do` block, after the `changeProject()` call but before `setMilestone()` and `updateStatus()`. This ensures that if `changeProject()` fails, no direct mutations are pending. If a later step fails, the direct mutations are unsaved and can be reverted by `rollback()`.

**Approach rationale:** The `changeProject()` call must happen first because it saves internally and the project change is a prerequisite for milestone validation. Direct mutations are applied after that save succeeds but before subsequent saves, so they remain unsaved and revertable if a later step fails.

**Alternatives considered:**
- Refactoring service methods to not save internally -- rejected because it would change the service API contract and affect all callers
- Capturing original values and manually reverting on failure -- rejected because `rollback()` already handles this correctly when mutations are properly ordered

## Regression Test

**Test file:** `Transit/TransitTests/TaskEditSaveErrorTests.swift`
**Test names:** `directMutationsBeforeServiceCallArePersistedByIntermediateSave`, `directMutationsAfterServiceCallAreRevertedByRollback`

**What it verifies:** The first test demonstrates the bug: direct mutations applied before a service save are persisted and cannot be rolled back. The second test verifies the fix: direct mutations applied after a service save remain unsaved and are correctly reverted by rollback.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/TaskDetail/TaskEditView.swift` | Move direct property mutations inside `do` block, after `changeProject()` |
| `Transit/TransitTests/TaskEditSaveErrorTests.swift` | Add two regression tests for T-378 partial persistence scenario |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- In save methods that call multiple service methods with internal saves, apply direct model mutations as late as possible -- after any intermediate saves
- Treat `modelContext.save()` inside service methods as flushing all pending mutations on the shared context, not just the service's own changes
- Consider documenting the "save ordering" requirement in the agent notes for UI views

## Related

- Transit ticket: T-378
- Previous fix: T-148 (task-edits-ignore-save-failures)
