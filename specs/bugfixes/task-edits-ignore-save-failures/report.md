# Bugfix Report: Task Edits Ignore Save Failures

**Date:** 2026-02-19
**Status:** Fixed

## Description of the Issue

When editing a task in `TaskEditView`, the `save()` method used `try?` for both `taskService.updateStatus()` and `modelContext.save()`, silently discarding any errors. The view always called `dismissAll()` regardless of whether the save succeeded, so the user received no feedback when a save failed and their edits could be silently lost.

**Reproduction steps:**
1. Open a task and tap Edit
2. Modify task properties (name, description, type, status, etc.)
3. Tap Save while the underlying SwiftData/CloudKit save would fail (e.g., due to sync conflict)
4. Observe: the editor dismisses with no error, but the changes are not persisted

**Impact:** Data loss -- users could believe their edits were saved when they were not.

## Investigation Summary

- **Symptoms examined:** `TaskEditView.save()` at lines 244-255 used `try?` to call both `taskService.updateStatus(task:to:)` and `modelContext.save()`, then unconditionally called `dismissAll()`.
- **Code inspected:** `TaskEditView.swift`, `TaskService.swift`, `StatusEngine.swift`, `ProjectEditView.swift` (for error handling pattern reference), `CommentsSection.swift` (for error handling pattern reference).
- **Hypotheses tested:** The `try?` usage was the sole cause -- confirmed by tracing the call chain.

## Discovered Root Cause

The `save()` method in `TaskEditView` used `try?` (optional try) for both save paths, converting thrown errors into `nil` and discarding them. The `dismissAll()` call was outside any conditional, so it executed regardless of save outcome.

**Defect type:** Silent error suppression

**Why it occurred:** The original implementation prioritised a simple dismiss-on-save flow without considering failure cases.

**Contributing factors:** No error handling pattern was established when the view was first written. Other views (ProjectEditView, CommentsSection) were later updated with proper error alerts, but TaskEditView was missed.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/TaskDetail/TaskEditView.swift` -- Replaced `try?` with `do/catch` in `save()`. On success, `dismissAll()` is called. On failure, `modelContext.rollback()` reverts in-memory mutations and an error alert is shown to the user. Added `@State private var errorMessage: String?` and a `.alert` modifier following the established pattern from `CommentsSection` and `ProjectEditView`.

**Approach rationale:** Follows the existing error handling pattern already used in `CommentsSection` and `ProjectEditView` -- `errorMessage` state drives a `Binding<Bool>` for `.alert`. Rollback ensures the model is not left in a partially-mutated state. The editor stays open so the user can retry.

**Alternatives considered:**
- Logging errors without alerting the user -- rejected because users still would not know their edits were lost
- Throwing errors to a parent view -- rejected because SwiftUI sheets handle their own state; the alert pattern is simpler and consistent with existing views

## Regression Test

**Test file:** `Transit/TransitTests/TaskEditSaveErrorTests.swift`
**Test names:** `rollbackRevertsDirectPropertyMutationsOnTask`, `rollbackRevertsStatusChangeAfterUpdateStatusFailure`, `updateStatusErrorPropagatesAndIsNotSwallowed`, `rollbackRevertsMetadataChanges`

**What it verifies:** That `modelContext.rollback()` correctly reverts direct property mutations (name, description, type, metadata, status) on a task after a failed save -- the recovery path that the fixed `save()` method relies on.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/TaskDetail/TaskEditView.swift` | Replace `try?` with `do/catch`, add error alert, rollback on failure |
| `Transit/TransitTests/TaskEditSaveErrorTests.swift` | New regression test suite for rollback and error propagation |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

**Manual verification:**
- Build succeeds on macOS

## Prevention

**Recommendations to avoid similar bugs:**
- Avoid `try?` in save/persist operations -- use `do/catch` with user-facing error feedback
- The same `try?` pattern exists in `TaskDetailView.actionButtons` for `restore` and `abandon` operations -- these should be addressed separately
- Consider a SwiftLint custom rule or code review checklist item to flag `try?` on `modelContext.save()` calls

## Related

- Transit ticket: T-148
