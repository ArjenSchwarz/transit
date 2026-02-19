# Bugfix Report: Project Creation Ignores Save Errors

**Date:** 2026-02-19
**Status:** Fixed

## Description of the Issue

`ProjectService.createProject` used `try? context.save()` to persist a newly created project. Because the error was discarded with `try?`, the method always returned a project object even if the save failed. The UI would then dismiss the creation form as if the operation succeeded, but the project would not persist across app restarts.

**Reproduction steps:**
1. Trigger a `ModelContext.save()` failure during project creation (e.g., storage full, CloudKit conflict)
2. Observe that the UI dismisses the creation form without showing an error
3. Restart the app and observe the project is missing

**Impact:** Data loss — users believe project creation succeeded when it silently failed. The project appears in the UI temporarily (it exists in the in-memory context) but is not persisted.

## Investigation Summary

- **Symptoms examined:** `ProjectService.createProject` return behavior when `context.save()` fails
- **Code inspected:** `ProjectService.swift`, `ProjectEditView.swift`
- **Hypotheses tested:** Confirmed that `try?` on line 42 swallows all save errors and returns the project regardless

## Discovered Root Cause

`try? context.save()` on line 42 of `ProjectService.createProject` discards the error from `ModelContext.save()`. The method signature declares `throws`, but only the duplicate-name check (line 38) could actually throw. Save failures were silently ignored.

**Defect type:** Silent error swallowing

**Why it occurred:** The original implementation used `try?` as a convenience pattern, likely because save failures were considered unlikely during development with in-memory stores.

**Contributing factors:** The method's `throws` declaration gave callers (like `ProjectEditView`) the false impression that all errors were propagated. `ProjectEditView` already had a generic error handler (`catch { errorMessage = "Failed to create project." }`) that was never reachable.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/ProjectService.swift:42-47` — Replaced `try? context.save()` with `try context.save()` wrapped in a do-catch that deletes the inserted project from the context on failure, then re-throws
- `Transit/Transit/Views/Settings/ProjectEditView.swift:26,33` — Changed alert title from "Duplicate Project" to "Error" since save errors are no longer limited to duplicate names

**Approach rationale:** The do-catch with rollback ensures that if `context.save()` fails, the project is removed from the in-memory context. Without this cleanup, a phantom project would remain in the context and could be persisted by a later save call, leading to inconsistent state.

**Alternatives considered:**
- Simply changing `try?` to `try` without rollback — rejected because the inserted-but-unsaved project would remain in the context as a pending change, potentially persisting on a later save
- Wrapping in a child context / transaction — rejected as over-engineering for this scenario

## Regression Test

**Test file:** `Transit/TransitTests/ProjectServiceTests.swift`
**Test name:** `createProjectPersistsViaSave`

**What it verifies:** After `createProject` succeeds, the project is fetchable and the context has no pending changes (confirming `context.save()` was called, not silently skipped).

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/ProjectService.swift` | Replace `try? context.save()` with error-propagating save and rollback on failure |
| `Transit/Transit/Views/Settings/ProjectEditView.swift` | Generalize alert title from "Duplicate Project" to "Error" |
| `Transit/TransitTests/ProjectServiceTests.swift` | Add regression test verifying save is committed |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- Avoid `try?` on persistence operations (`context.save()`, database writes) — errors should always propagate or be explicitly handled
- When inserting into a SwiftData context and then saving, always roll back the insert if the save fails

## Related

- Transit ticket: T-117
