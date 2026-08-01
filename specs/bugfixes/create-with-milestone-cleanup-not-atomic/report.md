# Bugfix Report: Create-with-milestone cleanup is not atomic

**Date:** 2026-08-01
**Status:** Investigating

## Description of the Issue

MCP `create_task`, `CreateTaskIntent`, and `AddTaskSheet.persist` persist a new task before assigning its optional milestone in a second save. If milestone assignment fails, each caller attempts a compensating task deletion. That deletion also requires a save and can fail for the same storage reason, leaving a task persisted even though creation reported failure.

**Reproduction steps:**
1. Create a task with a valid milestone through MCP, CreateTaskIntent, or AddTaskSheet.
2. Allow the task's first save to succeed.
3. Make the milestone-assignment save fail, then make the compensating deletion save fail.
4. Observe that the caller reports failure while the task from the first save remains persisted without the requested aggregate state.

**Impact:** Failed create retries can produce hidden tasks or duplicate tasks because the caller cannot distinguish the persisted partial create from a fully rejected operation.

## Investigation Summary

- **Symptoms examined:** All three create surfaces use pre-validation followed by task save, milestone save, and best-effort deletion.
- **Code inspected:** `TaskService.createTask`, `MilestoneService.setMilestone`, `MCPToolHandler.handleCreateTask`, `CreateTaskIntent.execute`, `AddTaskSheet.persist`, and existing save-failure helpers/tests.
- **Hypotheses tested:** Milestone pre-validation prevents lookup and project-mismatch orphans, but cannot make two persistence operations atomic. `insertOrDelete` correctly removes a newly inserted task after a failed first save, while compensating deletion cannot undo an already committed save when its own save fails.

## Discovered Root Cause

Aggregate creation is split across service boundaries: `TaskService.createTask` inserts and saves the task, then each surface calls `MilestoneService.setMilestone`, which mutates and saves again. Error recovery is therefore a third persistence operation rather than rollback of one failed transaction.

**Defect type:** Non-atomic composite persistence operation

**Why it occurred:** Earlier fixes added milestone pre-validation and compensating deletion, addressing validation failures but retaining a create-then-update sequence. SwiftData's shared context and fallible saves mean a later delete cannot guarantee reversal of the first committed save.

**Contributing factors:** The create save seam was only available as a per-call parameter on `TaskService.createTask`, so the three surface entry points could not test whether a milestone was attached before their persistence boundary.

## Resolution for the Issue

Pending implementation.

## Regression Test

**Test files:**
- `Transit/TransitTests/MCPMilestoneIntegrationTests.swift`
- `Transit/TransitTests/CreateTaskIntentMilestoneTests.swift`
- `Transit/TransitTests/AddTaskSheetSaveErrorTests.swift`

**What they verify:** Each surface reaches one task-creation save with the requested milestone already attached. When that save seam throws, no task remains in the context or appears after a later unrelated save.

**Run command:** `make test-quick`

## Affected Files

Pending implementation.

## Verification

**Automated:**
- [ ] Regression tests fail before the fix
- [ ] Regression tests pass after the fix
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Inspect all three create surfaces to confirm they delegate milestone application and persistence to `TaskService`.

## Prevention

- Treat a task plus its requested initial relationships as one aggregate insert.
- Expose persistence failure seams at the service boundary used by real surfaces.
- Avoid compensating saves when the aggregate can be constructed before its first persistence operation.

## Related

- Transit T-1768
- T-240, T-558, and T-855: earlier pre-validation and compensating-deletion fixes
- T-452 and T-486: create-save failure cleanup requirements
