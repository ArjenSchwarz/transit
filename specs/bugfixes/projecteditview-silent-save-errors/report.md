# Bugfix Report: ProjectEditView Silent Save Errors

**Date:** 2026-02-20
**Status:** Fixed

## Description of the Issue

When editing an existing project in `ProjectEditView`, the `save()` method used `try? modelContext.save()` and then unconditionally called `dismiss()`. If the save failed, the user received no error feedback, the sheet closed, and edits appeared to succeed but were lost on the next context refresh.

This is the same class of bug that T-148 fixed for `TaskEditView`, but `ProjectEditView` was not included in that fix.

**Reproduction steps:**
1. Open an existing project and edit its name, description, or other fields
2. Tap Save while the underlying SwiftData/CloudKit save would fail (e.g., due to sync conflict)
3. Observe: the editor dismisses with no error, but the changes are not persisted

**Impact:** Data loss -- users could believe their edits were saved when they were not.

## Investigation Summary

- **Symptoms examined:** `ProjectEditView.save()` at line 173 used `try? modelContext.save()`, then called `dismiss()` unconditionally at line 190.
- **Code inspected:** `ProjectEditView.swift`, `TaskEditView.swift` (for the T-148 fix pattern), `ProjectService.swift`.
- **Hypotheses tested:** The `try?` usage was the sole cause -- confirmed by tracing the call chain. The create-new-project path already had proper `do/catch` error handling; only the edit-existing-project path was affected.

## Discovered Root Cause

The `save()` method in `ProjectEditView` used `try?` (optional try) for `modelContext.save()` in the edit path, converting thrown errors into `nil` and discarding them. The `dismiss()` call was outside the conditional block, so it executed regardless of save outcome.

**Defect type:** Silent error suppression

**Why it occurred:** The edit-existing-project path was written with `try?` for convenience, while the create-new-project path in the same function already had proper `do/catch`. When T-148 fixed this pattern in `TaskEditView`, `ProjectEditView` was not included in the fix.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/Settings/ProjectEditView.swift` -- Replaced `try? modelContext.save()` with `do/catch` in the edit path of `save()`. On success, `dismiss()` is called as before. On failure, `modelContext.rollback()` reverts in-memory mutations, an error message is shown via the existing alert, and the view stays open so the user can retry.

**Approach rationale:** Follows the same pattern established by the T-148 fix in `TaskEditView` and already used in the create path of `ProjectEditView`. Rollback ensures the model is not left in a partially-mutated state. The editor stays open so the user can retry.

**Alternatives considered:**
- Logging errors without alerting the user -- rejected because users would still not know their edits were lost
- Throwing errors to a parent view -- rejected because the view already has an error alert mechanism in place

## Regression Test

**Test file:** `Transit/TransitTests/ProjectEditSaveErrorTests.swift`
**Test names:** `rollbackRevertsNameChangeOnProject`, `rollbackRevertsDescriptionChangeOnProject`, `rollbackRevertsAllPropertyChangesOnProject`, `rollbackRevertsGitRepoRemoval`

**What it verifies:** That `modelContext.rollback()` correctly reverts direct property mutations (name, description, gitRepo, colorHex) on a project after a failed save -- the recovery path that the fixed `save()` method relies on.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Settings/ProjectEditView.swift` | Replace `try?` with `do/catch`, add rollback on failure, surface error to user |
| `Transit/TransitTests/ProjectEditSaveErrorTests.swift` | New regression test suite for rollback of project properties |
| `specs/bugfixes/projecteditview-silent-save-errors/report.md` | Bugfix report |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (`make test-quick`)
- [x] Linters/validators pass (`make lint`)

**Manual verification:**
- Build succeeds on macOS

## Prevention

**Recommendations to avoid similar bugs:**
- Avoid `try?` in save/persist operations -- use `do/catch` with user-facing error feedback
- When fixing a pattern in one view, audit all views for the same pattern

## Related

- Transit ticket: T-154
- Prior fix: T-148 (same bug in TaskEditView)
