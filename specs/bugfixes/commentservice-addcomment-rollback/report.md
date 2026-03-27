# Bugfix Report: CommentService addComment should rollback on save failure

**Date:** 2026-03-27
**Status:** Fixed

## Description of the Issue

`CommentService.addComment(save: true)` inserts a `Comment` into the model context and calls `modelContext.save()`, but if the save throws, the error propagates without cleaning up the inserted comment. The orphaned comment remains in the context and can be persisted by a subsequent unrelated `save()` call.

**Reproduction steps:**
1. Call `addComment(to:content:authorName:isAgent:)` with `save: true` (default)
2. Have `modelContext.save()` fail (e.g., due to a CloudKit sync conflict)
3. The error is thrown, but the comment remains inserted in the model context
4. A later `save()` from any code path persists the orphaned comment

**Impact:** Data integrity issue. Comments could be silently persisted without the caller knowing the operation succeeded, or persisted in an inconsistent state alongside unrelated mutations.

## Investigation Summary

- **Symptoms examined:** The `addComment` method lacked error handling around `modelContext.save()`, unlike `deleteComment` and `deleteComments` in the same file
- **Code inspected:** `CommentService.swift`, `TaskService.swift`, `MilestoneService.swift`, `ModelContext+SafeRollback.swift`
- **Hypotheses tested:** Compared the save-failure handling patterns across all services

## Discovered Root Cause

The `addComment` method was missing a `do/catch` block around the `modelContext.save()` call. When save failed, the inserted comment was left in the model context.

**Defect type:** Missing error handling

**Why it occurred:** The original implementation used a simple `try modelContext.save()` without wrapping it in `do/catch`. Other creation methods (`TaskService.createTask`, `MilestoneService.createMilestone`) were fixed in T-486 to delete inserted objects on save failure, but `addComment` was not updated.

**Contributing factors:** The `save: Bool` parameter type made it impossible to inject a failing save for testing, so the gap was not caught by tests.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/CommentService.swift:37` - Changed `save` parameter from `Bool` to `((ModelContext) throws -> Void)?` with default `{ try $0.save() }`. Added `do/catch` that deletes the inserted comment on save failure.
- `Transit/Transit/Services/TaskService.swift:144` - Updated call site from `save: false` to `save: nil`
- `Transit/TransitTests/CommentServiceTests.swift` - Updated `save: false` to `save: nil`, added two regression tests

**Approach rationale:** The injectable closure pattern matches `TaskService.createTask` and `MilestoneService.createMilestone`. Using `modelContext.delete(comment)` on failure (rather than `safeRollback()`) follows the project convention for creation operations (see T-452: `safeRollback()` does not re-fault `@Model` properties reliably).

**Alternatives considered:**
- `safeRollback()` on failure - Rejected per T-452: rollback does not re-fault `@Model` properties for newly created objects, and would discard unrelated unsaved mutations from other code paths sharing the same context
- Keep `save: Bool` and wrap in `do/catch` - Would fix the bug but not enable test coverage of the failure path

## Regression Test

**Test file:** `Transit/TransitTests/CommentServiceTests.swift`
**Test name:** `addComment_deletesInsertedCommentOnSaveFailure`

**What it verifies:** When the save closure throws, the inserted comment is deleted from the context so it cannot be persisted by a later save.

**Paired test:** `addComment_succeedsWhenSaveWorks` confirms the injectable closure works correctly on the success path.

**Run command:** `make test-quick` (or target `TransitTests/CommentServiceTests`)

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/CommentService.swift` | Changed `save` parameter to injectable closure, added delete-on-failure handling |
| `Transit/Transit/Services/TaskService.swift` | Updated `addComment` call from `save: false` to `save: nil` |
| `Transit/TransitTests/CommentServiceTests.swift` | Updated existing test, added two regression tests |

## Verification

**Automated:**
- [x] Regression test written (cannot run due to pre-existing build failure in TransitApp.swift)
- [ ] Full test suite passes (blocked by pre-existing build error on main)
- [x] Linters/validators pass

**Note:** A pre-existing `Sendable` error in `TransitApp.swift:85` prevents the test suite from running on both main and this branch. The production code compiles successfully (`make build-macos` passes).

## Prevention

**Recommendations to avoid similar bugs:**
- All `modelContext.save()` calls in service creation methods should be wrapped in `do/catch` with cleanup
- Use injectable save closures for creation methods to enable testing of failure paths
- Consider a linting rule or code review checklist item for unguarded `modelContext.save()` calls

## Related

- T-486: Original rollback-on-save-failure fix for TaskService and MilestoneService
- T-452: Discovery that `safeRollback()` does not work reliably for creation operations
