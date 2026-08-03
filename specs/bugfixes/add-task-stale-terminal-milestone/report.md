# Bugfix Report: Add Task Stale Terminal Milestone

**Date:** 2026-08-04
**Status:** Investigating

## Description of the Issue

Add Task retained an in-memory milestone selection after that milestone became Done or Abandoned in another window, MCP call, or synced context. The picker correctly stopped offering the milestone because it displays only open records, but saving still persisted a new task assigned to the stale terminal model.

**Reproduction steps:**
1. Open Add Task and select an open milestone.
2. In another context, change the milestone to Done or Abandoned.
3. Return to the still-open Add Task form and save.
4. Observe that a new task is persisted against the terminal milestone.

**Impact:** New tasks can be added to closed milestones, making the Add Task picker’s open-only contract unreliable.

## Investigation Summary

- **Symptoms examined:** The picker filters to open milestones but its UUID binding keeps the selected model when it disappears from the options.
- **Code inspected:** `AddTaskSheet`, `AddTaskSheet+Save`, `TaskService.createTask`, `MilestoneService`, and the dashboard milestone filter.
- **Hypotheses tested:** The defect is not a dashboard filter issue (T-1825). The task creation path validates only project identity before awaiting display-ID allocation and never checks the milestone’s current status.

## Discovered Root Cause

**Defect type:** Time-of-check/time-of-use validation gap with stale cross-context model state.

**Why it occurred:**
1. The form captured a `Milestone` object while its status was open.
2. Another context committed a terminal status while the form’s context retained the clean, stale object.
3. `TaskService.createTask` checked only the stale object’s project identity before awaiting display-ID allocation.
4. The task was inserted and saved without re-reading current milestone state at the pre-persistence boundary.

**Contributing factors:** UI option filtering and `onChange` cannot guard against an external status change after selection or while an awaited operation is in progress.

## Resolution for the Issue

Pending implementation. The intended fix is a final task-creation validation after the allocation await that combines live pending state with a fresh committed-store milestone read and rejects terminal or cross-project selections before task insertion.

## Regression Test

**Test file:** `Transit/TransitTests/AddTaskStaleMilestoneTests.swift`
**Test name:** `persistRejectsMilestoneClosedAfterSelectionBeforeSaveWithoutInsertingTask`

**What it verifies:** A gated display-ID allocation permits a peer context to close a formerly selected milestone deterministically. The Add Task persistence path must reject the stale selection and leave no pending or committed task.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|---|---|
| `Transit/TransitTests/AddTaskSheetSaveErrorTests.swift` | Adds the deterministic red regression test. |
| `Transit/Transit/Services/TaskService.swift` | Pending service-layer revalidation at task-creation persistence boundary. |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Pending implementation.

## Prevention

- Validate mutable relationship invariants at the final persistence boundary, not only while collecting UI state.
- Combine a transient committed-store read with live context state when a selected SwiftData model may be stale after a cross-window or CloudKit update.

## Related

- T-2037
- T-1825 (separate dashboard terminal-filter behavior; intentionally unchanged)
