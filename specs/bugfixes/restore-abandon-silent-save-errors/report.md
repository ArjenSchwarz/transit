# Bugfix Report: Restore and Abandon Actions Silently Discard Save Errors

**Date:** 2026-02-20
**Status:** Fixed

## Description of the Issue

Three locations silently discard save errors using `try?`, causing the UI to dismiss without feedback when a save fails:

1. **TaskDetailView.actionButtons** -- `try? taskService.restore(task:)` followed by unconditional `dismiss()`
2. **TaskDetailView.actionButtons** -- `try? taskService.abandon(task:)` followed by unconditional `dismiss()`
3. **ProjectEditView.save()** -- `try? modelContext.save()` for existing project edits, followed by unconditional `dismiss()`

**Reproduction steps:**
1. Open a task detail view and tap Abandon (or Restore for abandoned tasks)
2. If the underlying SwiftData save fails (e.g., CloudKit sync conflict), the sheet dismisses with no error
3. The user believes the action succeeded, but the status change was not persisted

Same pattern for editing an existing project: modify properties, tap Save, sheet dismisses even if the save failed.

**Impact:** Silent data loss -- users get no feedback when operations fail.

## Investigation Summary

- **Symptoms examined:** `try?` usage in `TaskDetailView.actionButtons` (lines 173, 179) and `ProjectEditView.save()` (line 173)
- **Code inspected:** `TaskDetailView.swift`, `ProjectEditView.swift`, `TaskService.swift` (abandon/restore methods), `TaskEditView.swift` (reference for the T-148 fix pattern)
- **Pattern reference:** T-148 fixed the identical bug in `TaskEditView.save()` using `do/catch`, error alert, and rollback

## Discovered Root Cause

The `try?` operator suppresses thrown errors by converting them to `nil`. The `dismiss()` call sits outside any conditional, executing regardless of save outcome. This is the same defect pattern that T-148 fixed in TaskEditView but these three call sites were missed.

**Defect type:** Silent error suppression

**Why it occurred:** The original implementation prioritised a simple dismiss-on-action flow without considering failure cases.

**Contributing factors:** The T-148 fix explicitly noted these remaining instances in its prevention section but they were not addressed at that time.

## Resolution for the Issue

**Changes made:**

1. **`Transit/Transit/Views/TaskDetail/TaskDetailView.swift`** -- Added `@State private var errorMessage: String?` and an `.alert` modifier. Replaced `try?` with `do/catch` in both restore and abandon button actions. On success, `dismiss()` is called. On failure, `errorMessage` is set to show an alert. The view stays open so the user can retry or dismiss manually.

2. **`Transit/Transit/Views/Settings/ProjectEditView.swift`** -- Replaced `try? modelContext.save()` with `do/catch` in the existing-project save path. On failure, `modelContext.rollback()` reverts in-memory mutations and `errorMessage` is set. The view stays open. The `errorMessage` state and `.alert` modifier already existed from previous work.

**Approach rationale:** Follows the error handling pattern established by T-148 in TaskEditView: `errorMessage` state drives a `.alert` via `Binding<Bool>` (`$errorMessage.isPresent`). For ProjectEditView, rollback ensures the model is not left with partially-mutated properties. For TaskDetailView, the TaskService methods handle their own save, so no rollback is needed at the view level.

**Alternatives considered:**
- Logging errors without alerting the user -- rejected because users would still not know the operation failed
- Showing a toast instead of an alert -- rejected because the alert pattern is consistent with all other views in the app

## Regression Test

**Test file:** `Transit/TransitTests/ActionButtonSaveErrorTests.swift`
**Test names:** `rollbackRevertsAbandonStatusChange`, `rollbackRevertsRestoreStatusChange`, `abandonIsThrowingAndPropagatesErrors`, `restoreIsThrowingAndPropagatesErrors`, `rollbackRevertsDirectProjectPropertyMutations`

**What it verifies:** That `modelContext.rollback()` correctly reverts status changes from abandon/restore and direct property mutations on projects. Also documents the throwing contract of TaskService.abandon() and TaskService.restore() that the view layer depends on.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/TaskDetail/TaskDetailView.swift` | Replace `try?` with `do/catch` in action buttons, add error alert |
| `Transit/Transit/Views/Settings/ProjectEditView.swift` | Replace `try?` with `do/catch` for existing project save, add rollback on failure |
| `Transit/TransitTests/ActionButtonSaveErrorTests.swift` | New regression test suite for rollback and error propagation |

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
- Consider a SwiftLint custom rule or code review checklist item to flag `try?` on `modelContext.save()` or service method calls
- All instances of the silent-save-error pattern identified in the T-148 audit are now fixed

## Related

- Transit ticket: T-150
- Previous fix: T-148 (task-edits-ignore-save-failures)
