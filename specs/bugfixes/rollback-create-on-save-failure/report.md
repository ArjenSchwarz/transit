# Bugfix Report: rollback-create-on-save-failure

**Date:** 2025-07-14
**Ticket:** T-486
**Status:** Fixed

## Description of the Issue

`TaskService.createTask` and `MilestoneService.createMilestone` insert model objects into the SwiftData `ModelContext` and call `modelContext.save()` without handling save failures. If the save throws, the unsaved model remains registered in the shared main context and may later be persisted by an unrelated save operation, leading to ghost records.

**Reproduction steps:**
1. Call `createTask` or `createMilestone`
2. Have `modelContext.save()` fail (e.g., CloudKit constraint violation)
3. Perform any other operation that calls `modelContext.save()`
4. Observe the orphaned task/milestone is now persisted despite the original create failing

**Impact:** Data integrity — phantom tasks/milestones could appear in the kanban board or query results without the user ever successfully creating them.

## Investigation Summary

- **Symptoms examined:** Both `createTask` and `createMilestone` use a bare `try modelContext.save()` after `modelContext.insert()`, propagating the error but leaving the inserted object in the context.
- **Code inspected:** `TaskService.swift`, `MilestoneService.swift`, `ProjectService.swift` (which already has the correct pattern), all update/delete methods in both services.
- **Hypotheses tested:** Confirmed that `ProjectService.createProject` already implements delete-on-failure correctly. Confirmed that update methods use `modelContext.rollback()` (appropriate for mutations on existing objects). Confirmed that `delete()` is the right approach for create operations since `rollback()` would discard all unsaved context changes, not just the failed insert.

## Discovered Root Cause

**Defect type:** Missing error handling (incomplete atomicity)

**Why it occurred:** The create methods were written with the assumption that `modelContext.save()` would always succeed, or that the thrown error was sufficient. The side effect of the inserted object remaining in the context was overlooked.

**Contributing factors:** SwiftData's `ModelContext.insert()` is not transactional — once called, the object is registered in the context regardless of whether `save()` succeeds. Other services (ProjectService) had already fixed this, but the pattern wasn't applied consistently.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/TaskService.swift:102-108` — Wrapped `save()` in do/catch; on failure, calls `modelContext.delete(task)` before rethrowing
- `Transit/Transit/Services/MilestoneService.swift:74-80` — Same pattern: `modelContext.delete(milestone)` on save failure
- Both methods gained an injectable `save` closure parameter (defaulting to `{ try $0.save() }`) for testability, consistent with the existing `promoteProvisionalTasks`/`promoteProvisionalMilestones` pattern

**Approach rationale:** `delete()` is used instead of `rollback()` because rollback would discard ALL unsaved changes on the shared context, not just the failed insert. This matches the existing `ProjectService.createProject` pattern.

**Alternatives considered:**
- `modelContext.rollback()` — Too broad; would discard unrelated pending changes on the shared context
- Child `ModelContext` for isolation — Overly complex for this use case; SwiftData child contexts add relationship merging complications

## Regression Test

**Test file:** `Transit/TransitTests/TaskServiceTests.swift`
**Test name:** `createTaskDeletesInsertedObjectOnSaveFailure`

**Test file:** `Transit/TransitTests/MilestoneServiceTests.swift`
**Test name:** `createMilestoneDeletesInsertedObjectOnSaveFailure`

**What they verify:** When save fails during create, the inserted object is removed from the context (fetch returns empty). Also verifies the error propagates to the caller.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/TaskService.swift` | Add delete-on-failure to `createTask`, injectable `save` parameter |
| `Transit/Transit/Services/MilestoneService.swift` | Add delete-on-failure to `createMilestone`, injectable `save` parameter |
| `Transit/TransitTests/TaskServiceTests.swift` | Add regression test for save failure rollback |
| `Transit/TransitTests/MilestoneServiceTests.swift` | Add regression test for save failure rollback |

## Verification

**Automated:**
- [x] Regression tests pass
- [x] Full test suite passes (688 tests)
- [x] Linters pass (0 violations)

## Prevention

**Recommendations to avoid similar bugs:**
- Always wrap `modelContext.save()` in do/catch after `modelContext.insert()` — use `delete()` on the inserted object in the catch block
- Reference `ProjectService.createProject` as the canonical pattern for atomic create operations
- Consider a shared helper or protocol extension that encapsulates the insert-save-or-delete pattern

## Related

- T-486: Rollback createTask/createMilestone on save failure
- `ProjectService.createProject` — existing correct implementation of this pattern
- `PromotionRollbackTests` — related injectable save closure testing pattern
