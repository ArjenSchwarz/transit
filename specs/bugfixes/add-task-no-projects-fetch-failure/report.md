# Bugfix Report: Add Task No-Projects Fetch Failure

**Date:** 2026-08-05
**Status:** Investigating

## Description of the Issue

When the visual Add Task shortcut has no selected project, it asks `ProjectService.hasAnyProjects()` whether setup is empty. A SwiftData project-table fetch failure is silently converted to `false`, so the shortcut reports `NO_PROJECTS` and tells the user to create a project even though storage could be unavailable.

**Reproduction steps:**
1. Inject a project fetcher that throws a deterministic storage error.
2. Run `AddTaskIntent.execute` with no selected project.
3. Observe that the pre-fix implementation returns `VisualIntentError.noProjects` rather than an internal storage error.

**Impact:** A retryable data-access failure is misclassified as a setup problem, sending Shortcuts users toward the wrong recovery action.

## Investigation Summary

- **Symptoms examined:** T-1749’s no-selection path; direct regression fails on the merged baseline.
- **Code inspected:** `ProjectService.hasAnyProjects()`, `AddTaskIntent.execute`, and T-1657’s `ProjectLookupStorageFailureSurfaceTests`.
- **Hypotheses tested:** T-1657/#224 correctly maps a storage failure for a selected `ProjectEntity`; it does not cover or alter the separate no-selection existence fetch. That selected-project path is T-2078’s stale-selection context and remains out of scope.

## Discovered Root Cause

`ProjectService.hasAnyProjects()` wraps `modelContext.fetch` in `try?`, replacing a failed fetch with an empty array. `AddTaskIntent` treats the resulting `false` as evidence that no projects exist.

**Defect type:** Silent error handling / incorrect error classification.

**Why it occurred:**
1. The existence check must fetch the project table.
2. The fetch was made non-throwing with `try?`.
3. Failure became an empty result.
4. Empty result selected the `NO_PROJECTS` branch.
5. The visual intent had no opportunity to distinguish storage failure from a genuine empty store.

**Contributing factors:** The existing injectable project fetch seam was used by lookup operations but not by the existence check, so the no-selection path was not regression-tested.

## Resolution for the Issue

Pending implementation.

## Regression Test

**Test file:** `Transit/TransitTests/ProjectLookupStorageFailureSurfaceTests.swift`
**Test name:** `visualAddTaskReportsStorageFailureWhenProjectExistenceFetchFails`

**What it verifies:** An injected project-table fetch failure with no selected project produces `VisualIntentError.storageFailure` / `INTERNAL_ERROR`, not `NO_PROJECTS`, and creates no task.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/ProjectService.swift` | Pending: expose fetch failure from the project-existence check through the existing fetch seam. |
| `Transit/Transit/Intents/Visual/AddTaskIntent.swift` | Pending: map existence-check failures to the visual internal storage error. |
| `Transit/TransitTests/ProjectLookupStorageFailureSurfaceTests.swift` | Added exact visual no-selection failure regression. |

## Verification

**Automated:**
- [x] Regression fails before the fix
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:** The injected failing-fetcher test exercises the same visual intent path that Shortcuts invokes.

## Prevention

- Do not use `try?` to turn storage reads that drive user-visible decisions into empty data.
- Route all project reads covered by `ProjectService` through its injectable fetch seam when tests must distinguish failures from empty results.

## Related

- T-1749
- T-1657 / PR #224 (selected-project lookup failure handling)
- T-2078 (separate selected stale-project storage-failure mapping)
