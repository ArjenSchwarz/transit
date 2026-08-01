# Bugfix Report: Create-with-milestone cleanup is not atomic

**Date:** 2026-08-01
**Status:** Fixed

## Description of the Issue

MCP `create_task`, `CreateTaskIntent`, and `AddTaskSheet.persist` persisted a new task before assigning its optional milestone in a second save. If milestone assignment failed, each caller attempted a compensating task deletion. That deletion also required a save and could fail for the same storage reason, leaving a task persisted even though creation reported failure.

**Reproduction steps:**
1. Create a task with a valid milestone through MCP, CreateTaskIntent, or AddTaskSheet.
2. Allow the task's first save to succeed.
3. Make the milestone-assignment save fail, then make the compensating deletion save fail.
4. Observe that the caller reports failure while the task from the first save remains persisted without the requested aggregate state.

**Impact:** Failed create retries could produce hidden tasks or duplicates because the caller could not distinguish the persisted partial create from a fully rejected operation.

## Investigation Summary

- **Symptoms examined:** All three create surfaces used pre-validation followed by task save, milestone save, and best-effort deletion.
- **Code inspected:** `TaskService.createTask`, `MilestoneService.setMilestone`, `MCPToolHandler.handleCreateTask`, `CreateTaskIntent.execute`, `AddTaskSheet.persist`, and existing save-failure helpers/tests.
- **Hypotheses tested:** Milestone pre-validation prevents lookup and project-mismatch orphans, but cannot make two persistence operations atomic. `insertOrDelete` correctly removes a newly inserted task after a failed first save, while compensating deletion cannot undo an already committed save when its own save fails.

## Discovered Root Cause

Aggregate creation was split across service boundaries: `TaskService.createTask` inserted and saved the task, then each surface called `MilestoneService.setMilestone`, which mutated and saved again. Error recovery was therefore a third persistence operation rather than cleanup of one failed transaction.

**Defect type:** Non-atomic composite persistence operation

**Why it occurred:** Earlier fixes added milestone pre-validation and compensating deletion, addressing validation failures but retaining a create-then-update sequence. SwiftData's shared context and fallible saves mean a later delete cannot guarantee reversal of the first committed save.

**Contributing factors:** The create save seam was only available as a per-call parameter on `TaskService.createTask`, so the three surface entry points could not test whether a milestone was attached before their persistence boundary.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/TaskService.swift` — Added optional milestone aggregate creation, project validation, and an initializer-injected create-save seam. The task relationship is attached before `insertOrDelete` performs the only save.
- `Transit/Transit/MCP/MCPToolHandler.swift` — Passes the pre-resolved milestone to `TaskService.createTask`; removed the second save and best-effort task deletion.
- `Transit/Transit/Intents/CreateTaskIntent.swift` — Uses the same aggregate create path; removed milestone assignment and compensating deletion.
- `Transit/Transit/Views/AddTask/AddTaskSheet+Save.swift` — Delegates task plus selected milestone to `TaskService` in one call.

**Approach rationale:** Constructing the complete aggregate before insertion lets SwiftData persist the task and relationship in one save. The existing `insertOrDelete` helper removes the inserted task when that save fails, so no already-committed task needs a second fallible operation to reverse it.

**Alternatives considered:**
- Keep compensating deletion and retry it — rejected because retries cannot make two independent commits atomic and can still leave partial data.
- Roll back the shared context — rejected because creation uses `insertOrDelete` by design; context-wide rollback can discard unrelated edits and does not reliably re-fault new models (T-452/T-486).

## Regression Test

**Test files:**
- `Transit/TransitTests/MCPCreateTaskAtomicityTests.swift`
- `Transit/TransitTests/CreateTaskIntentMilestoneTests.swift`
- `Transit/TransitTests/AddTaskSheetSaveErrorTests.swift`

**Test names:**
- `createTaskWithMilestoneSaveFailureIsAtomic`
- `persistWithMilestoneIsAtomicWhenCreateSaveFails`

**What they verify:** Each surface reaches one task-creation save with the requested milestone already attached. When that save seam throws, no task remains in the context or appears after a later unrelated save.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/TaskService.swift` | Central aggregate create, milestone validation, injectable create-save seam |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Route MCP create through aggregate persistence |
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Route App Intent create through aggregate persistence |
| `Transit/Transit/Views/AddTask/AddTaskSheet+Save.swift` | Route UI create through aggregate persistence |
| `Transit/TransitTests/MCPCreateTaskAtomicityTests.swift` | MCP save-failure regression |
| `Transit/TransitTests/CreateTaskIntentMilestoneTests.swift` | App Intent save-failure regression |
| `Transit/TransitTests/AddTaskSheetSaveErrorTests.swift` | Add Task sheet save-failure regression |
| `Transit/TransitTests/MCPTestHelpers.swift` | Injectable MCP task-create save fixture |

## Verification

**Automated:**
- [x] Red phase confirmed: `make test-quick` failed before implementation because the required aggregate create seam did not exist.
- [x] Regression and macOS unit suite pass: `make test-quick`.
- [x] iOS and macOS builds pass: `make build`.
- [x] SwiftLint and SwiftData ownership guard pass: `make lint`.
- [ ] Full iOS simulator suite: `make test` compiled the changed code/tests but timed out while Xcode repeatedly failed to establish simulator/device debugger services (`DTDKRemoteDeviceConnection` secure-connection failures and missing LLDB version). No source test failure was reported before the environment timeout.
- [ ] UI suite: `make test-ui` was retried separately with a five-minute bound and hit the same `com.apple.mobile.notification_proxy` secure-connection and missing-LLDB failures before timing out.

**Manual verification:**
- Confirmed all three create surfaces pass the optional milestone into `TaskService.createTask`.
- Confirmed the create-specific `try? taskService.deleteTask(task)` paths were removed.

## Prevention

- Treat a task plus its requested initial relationships as one aggregate insert.
- Expose persistence failure seams at the service boundary used by real surfaces.
- Avoid compensating saves when the aggregate can be constructed before its first persistence operation.

## Related

- Transit T-1768
- T-240, T-558, and T-855: earlier pre-validation and compensating-deletion fixes
- T-452 and T-486: create-save failure cleanup requirements
