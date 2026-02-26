# Bugfix Report: Rollback Missing After Delete Save Failures

**Date:** 2026-02-26
**Status:** Fixed
**Ticket:** T-270

## Description of the Issue

`CommentService.deleteComment`, `CommentService.deleteComments`, and `MilestoneService.deleteMilestone` called `modelContext.save()` without rolling back on failure. If a save error occurred (e.g., CloudKit conflict), the context kept the deletion pending — the UI would reflect deletions that never persisted, and later saves could delete data unexpectedly.

**Reproduction steps:**
1. Delete a comment or milestone
2. Have `modelContext.save()` fail (e.g., due to CloudKit conflict)
3. The model context retains the pending deletion; UI shows the item as deleted
4. A subsequent successful save silently commits the stale deletion

**Impact:** Data loss — items could be permanently deleted without the user's knowledge on a later save operation.

## Investigation Summary

- **Symptoms examined:** Delete methods in CommentService and MilestoneService lacked rollback-on-error handling
- **Code inspected:** `CommentService.swift`, `MilestoneService.swift`, `TaskService.swift` (reference pattern)
- **Hypotheses tested:** Confirmed that other mutating methods in the same services (`updateMilestone`, `updateStatus`, `setMilestone`) and in `TaskService` already use the correct `do/catch` + `rollback()` pattern

## Discovered Root Cause

Three delete methods called `try modelContext.save()` directly without wrapping in a `do/catch` block, so on save failure the pending deletion remained in the context's dirty state.

**Defect type:** Missing error handling (inconsistent pattern application)

**Why it occurred:** The rollback pattern was applied to update methods but overlooked for delete methods during initial implementation.

**Contributing factors:** No compile-time enforcement that `save()` calls are paired with `rollback()` on failure.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/CommentService.swift:63-72` — Wrapped `deleteComment` save in `do/catch` with `rollback()`
- `Transit/Transit/Services/CommentService.swift:75-86` — Wrapped `deleteComments` save in `do/catch` with `rollback()`
- `Transit/Transit/Services/MilestoneService.swift:128-137` — Wrapped `deleteMilestone` save in `do/catch` with `rollback()`

**Approach rationale:** Mirrors the existing pattern used consistently in `updateMilestone`, `updateStatus`, `setMilestone`, and all `TaskService` mutating methods.

**Alternatives considered:**
- Extracting a shared `saveOrRollback()` helper — not chosen to keep changes minimal and consistent with existing code style

## Regression Test

No new regression tests added. The bug involves save failure scenarios that require injecting `ModelContext.save()` failures, which is not straightforward with SwiftData's in-memory test containers. The existing test suite validates that the delete methods continue to work correctly in the happy path.

**Existing tests verified:**
- `CommentServiceTests.deleteComment_removesFromStore`
- `CommentServiceTests.deleteComments_batchRemovesCorrectItems`
- `MilestoneServiceTests.deleteMilestoneRemovesFromContext`
- `MilestoneServiceTests.deleteMilestoneNullifiesTaskAssignment`

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/CommentService.swift` | Added rollback on save failure in `deleteComment` and `deleteComments` |
| `Transit/Transit/Services/MilestoneService.swift` | Added rollback on save failure in `deleteMilestone` |

## Verification

**Automated:**
- [x] Full test suite passes (`make test-quick`)
- [x] Linters pass (`make lint` — 0 violations)

## Prevention

**Recommendations to avoid similar bugs:**
- Audit all `modelContext.save()` call sites to ensure they use the `do/catch` + `rollback()` pattern
- Consider a code review checklist item: "Every `modelContext.save()` must be wrapped with rollback-on-error"

## Related

- T-270: Rollback missing after delete save failures in CommentService/MilestoneService
