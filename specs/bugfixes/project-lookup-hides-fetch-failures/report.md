# Bugfix Report: Project lookup hides fetch failures

**Date:** 2026-08-04
**Status:** Investigating

## Description of the Issue

`ProjectService.findProject(id:name:)` now exposes unreadable SwiftData storage as `ProjectLookupError.storageFailure`, but two callers still collapse that result into a caller-facing outcome. `QueryMilestonesIntent` returns a successful empty JSON array and the visual `AddTaskIntent` reports `PROJECT_NOT_FOUND`.

**Reproduction steps:**
1. Construct `ProjectService` with a deterministic `ModelFetching` seam that throws.
2. Query milestones with a project name, or create a visual task with a selected project.
3. Observe `[]` or a project-not-found error rather than an internal storage error.

**Impact:** Automations and Shortcuts users cannot distinguish retryable storage failure from a valid empty query or a stale project selection. The visual workflow offers the wrong remediation. Creation must not proceed while lookup is unreadable.

## Investigation Summary

### Phase 1 — Initial overview

Expected behavior is a source-appropriate storage error: JSON intents return `INTERNAL_ERROR`; MCP returns an error tool result; the visual intent reports an internal storage error. Missing projects, ambiguous names, malformed fields, UUID-over-name precedence, and no-mutation behavior must remain unchanged.

The targeted macOS regression test was red before implementation:

```text
ProjectLookupStorageFailureSurfaceTests.jsonQueryPathsReturnInternalErrorInsteadOfEmptyResultsWhenProjectLookupFails()
ProjectLookupStorageFailureSurfaceTests.visualAddTaskReportsInternalStorageErrorWithoutInsertionWhenProjectLookupFails()
```

### Phase 2 — Systematic inspection

- `Transit/Transit/Services/ProjectService.swift` catches both ID and name fetch errors and returns the existing `.storageFailure` case. The deterministic `fetcher` seam and direct service tests already exist.
- `Transit/Transit/Intents/IntentHelpers.swift` maps `.storageFailure` to `INTERNAL_ERROR`, preserving not-found, ambiguity, and malformed/no-identifier mappings.
- `CreateTaskIntent`, `CreateMilestoneIntent`, `QueryTasksIntent`, and all MCP project lookup call sites delegate through that mapping. New regression coverage confirms these paths already return the storage error before inserting tasks or milestones.
- `QueryMilestonesIntent.applyFilters` calls `findProject(name:)` but treats every failure as an empty result. This swallows both storage failure and the existing empty-result behavior for genuine not-found/ambiguous name filters.
- `AddTaskIntent.execute` treats every project lookup failure as `.projectNotFound`, conflating `storageFailure` with a stale selection.

### Phase 3 — Root cause analysis

1. Why do storage failures look like success or not-found? The two callers discard the `ProjectLookupError` case.
2. Why can they discard it? Their control flow was written when lookup callers only needed a project or fallback outcome.
3. Why is that no longer valid? `ProjectLookupError.storageFailure` is an explicit, tested distinction and T-1770 establishes that untyped persistence failures are `INTERNAL_ERROR` rather than validation/domain failures.
4. Why did shared mapping not prevent this? `QueryMilestonesIntent` bypasses `IntentHelpers.mapProjectLookupError` inside its filter helper, and visual intents require their own typed `VisualIntentError` mapping.

**Root cause:** two surface-specific error adapters failed to preserve the existing typed storage-failure result from `ProjectService`.

**Assumptions verified:** T-1770 (`ee8cfbc`) is an ancestor of this ticket branch. Its generic persistence convention is therefore the applicable baseline, not a change requiring a merge or duplicate seam.

## Resolution for the Issue

Pending implementation.

**Proposed changes:**
- Resolve the Query Milestones project filter before milestone retrieval. Use the project UUID for filtering, return `INTERNAL_ERROR` only for `.storageFailure`, and retain successful empty arrays for not-found/ambiguous name filters and project-ID precedence.
- Add a dedicated visual storage-failure error that maps to `INTERNAL_ERROR`; map only `.storageFailure` to it while preserving stale-selection `PROJECT_NOT_FOUND` behavior.

**Alternatives considered:**
- Map every lookup failure to internal error — rejected because it would regress not-found and ambiguity contracts.
- Change `ProjectService.findProject` to throw — rejected because it would widen a stable service API and duplicate its existing `Result`-based semantics.

## Regression Test

**Test file:** `Transit/TransitTests/ProjectLookupStorageFailureSurfaceTests.swift`

**Tests:**
- `jsonCreatePathsReturnInternalErrorWithoutInsertionWhenProjectLookupFails`
- `jsonQueryPathsReturnInternalErrorInsteadOfEmptyResultsWhenProjectLookupFails`
- `mcpCreateAndQueryPathsReturnStorageErrorsWithoutInsertionWhenProjectLookupFails`
- `visualAddTaskReportsInternalStorageErrorWithoutInsertionWhenProjectLookupFails`

**What it verifies:** The deterministic failing project fetch seam produces `INTERNAL_ERROR` or an MCP tool error as appropriate on every lookup surface, while creation paths leave no task or milestone in storage.

**Run command:** `make test-quick` (or a focused macOS `xcodebuild test` during red/green development)

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/QueryMilestonesIntent.swift` | Preserve storage failure while filtering by project name. |
| `Transit/Transit/Intents/Visual/AddTaskIntent.swift` | Distinguish a storage failure from a stale project. |
| `Transit/Transit/Intents/Visual/VisualIntentError.swift` | Represent visual storage failures as `INTERNAL_ERROR`. |
| `Transit/TransitTests/ProjectLookupStorageFailureSurfaceTests.swift` | Cross-surface parity and no-mutation regression coverage. |

## Verification

**Automated:**
- [x] Regression fails before the fix.
- [ ] Regression passes after the fix.
- [ ] Full macOS unit suite passes.
- [ ] Linters/validators pass.

**Manual verification:** Not required; deterministic in-memory SwiftData tests exercise the service seams and all automation/visual execution boundaries.

## Prevention

- New project lookup callers must branch explicitly on `ProjectLookupError.storageFailure` rather than use a catch-all fallback.
- Keep storage-failure seams at service boundaries and test the external error contract plus mutation state.

## Related

- T-1657
- T-1770 (`ee8cfbc`): generic persistence failures map to internal errors.
- `docs/agent-notes/technical-constraints.md`: SwiftData save/fetch recovery conventions.
