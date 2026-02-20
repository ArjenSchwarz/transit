# Bugfix Report: AddTaskSheet Dismisses Before Task Creation Completes

**Date:** 2026-02-20
**Status:** Fixed

## Description of the Issue

The `AddTaskSheet.save()` method called `dismiss()` immediately, then fired a detached `Task` to call `taskService.createTask`. The `_ = try await` inside the Task silently discarded any errors. If creation failed (display ID allocation timeout, save error, project not found), the sheet was already gone and the user received no feedback.

**Reproduction steps:**
1. Open the Add Task sheet
2. Fill in task details and tap Save
3. If `taskService.createTask` fails (e.g., due to CloudKit sync conflict, display ID allocation timeout)
4. Observe: the sheet dismisses with no error, but the task is not created

**Impact:** Data loss -- users could believe their task was created when it was not.

## Investigation Summary

- **Symptoms examined:** `AddTaskSheet.save()` at lines 188-207 called `dismiss()` on line 197 before the `Task` block containing `createTask`. The `Task` block used `_ = try await`, discarding both the result and any thrown error.
- **Code inspected:** `AddTaskSheet.swift`, `TaskService.swift` (createTask signatures), `TaskEditView.swift` (reference error handling pattern), `ProjectEditView.swift` (reference error handling pattern).
- **Pattern comparison:** `TaskEditView` and `ProjectEditView` already had the correct pattern (do/catch with error alert and rollback). `AddTaskSheet` was the outlier.

## Discovered Root Cause

The `save()` function was synchronous and used a fire-and-forget `Task` block for the async `createTask` call. This had two defects:

1. **Premature dismiss:** `dismiss()` was called before `createTask` completed, so the user lost the ability to retry on failure.
2. **Silent error suppression:** `_ = try await` in the detached Task discarded thrown errors with no user feedback.

**Defect type:** Race condition with silent error suppression.

**Why it occurred:** The original implementation treated task creation as a background operation that would always succeed, without considering failure cases.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/AddTask/AddTaskSheet.swift` -- Made `save()` async. The button action bridges to async via `Task { await save() }`. Task creation is awaited directly; `dismiss()` is called only on success. On failure, `errorMessage` is set to show an alert, keeping the sheet open for retry. Added `isSaving` state to disable the save button during the async operation, preventing double-taps.

**Approach rationale:** Follows the established error handling pattern from `TaskEditView` and `ProjectEditView` -- `errorMessage: String?` state drives a `Binding<Bool>` for `.alert` via the existing `Binding+IsPresent` extension. The sheet stays open on failure so the user can correct the issue or retry.

**Alternatives considered:**
- Keeping the fire-and-forget pattern but adding error logging -- rejected because users still would not know their task was not created
- Using a `@State var result: Result<...>?` pattern -- rejected because the `errorMessage` + `.alert` pattern is already established in the codebase

## Regression Test

**Test file:** `Transit/TransitTests/AddTaskSheetSaveErrorTests.swift`
**Test names:** `createTaskWithInvalidProjectIDThrowsProjectNotFound`, `createTaskWithEmptyNameThrowsInvalidName`, `noTaskPersistedWhenCreationFailsDueToInvalidProject`, `successfulCreationReturnsPersistableTask`

**What it verifies:** That `TaskService.createTask` errors propagate correctly (are not silently discarded), which is the contract the fixed `save()` method relies on. Also verifies that no task is persisted when creation fails.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/AddTask/AddTaskSheet.swift` | Await createTask before dismissing, add error alert, add isSaving guard |
| `Transit/TransitTests/AddTaskSheetSaveErrorTests.swift` | New regression test suite for error propagation |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (`make test-quick`)
- [x] Linters/validators pass (`make lint`)
- [x] Builds on both macOS and iOS

## Prevention

**Recommendations to avoid similar bugs:**
- Avoid fire-and-forget `Task` blocks for operations that can fail and require user feedback
- When dismissing sheets/views, always await the underlying operation first
- The same premature-dismiss pattern should be checked in other views that create or modify data

## Related

- Transit ticket: T-153
- Similar fix: T-148 (TaskEditView save error handling)
