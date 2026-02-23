# Bugfix Report: Drag/Drop to Done/Abandoned Resets Status/Timestamps

**Date:** 2026-02-23
**Status:** Fixed
**Ticket:** T-192

## Description of the Issue

Dragging a task within the Done/Abandoned column (a same-column drop) causes unintended mutations:

1. **Abandoned tasks become Done:** Dropping an abandoned task onto the Done/Abandoned column sets its status to `.done` because `DashboardColumn.doneAbandoned.primaryStatus` is `.done`.
2. **Timestamps reset on no-op drops:** Even when a done task is dropped on its own column, `StatusEngine.applyTransition` overwrites `lastStatusChangeDate` and `completionDate` to the current time, keeping old tasks artificially visible in the 48-hour window.

**Reproduction steps:**
1. Create a task and move it to Done
2. Note the completion timestamp
3. Drag the done task and drop it back onto the Done/Abandoned column
4. Observe: `completionDate` is reset to now
5. Create another task and abandon it
6. Drag the abandoned task within the Done/Abandoned column
7. Observe: task status changes from Abandoned to Done

**Impact:** Abandoned tasks silently lose their status. Done tasks get their timestamps reset, which affects the 48-hour visibility window and any reporting that relies on `completionDate`.

## Investigation Summary

- **Symptoms examined:** Abandoned tasks becoming done on same-column drop; timestamps resetting on no-op drops
- **Code inspected:** `DashboardView.swift` (`handleDrop`, `DashboardLogic.applyDrop`), `StatusEngine.swift` (`applyTransition`), `TaskStatus.swift` (`DashboardColumn.primaryStatus`)
- **Root cause identified via:** Code tracing the drag-drop path from `ColumnView.onDrop` through `DashboardLogic.applyDrop` to `StatusEngine.applyTransition`

## Discovered Root Cause

`DashboardLogic.applyDrop` unconditionally called `service.updateStatus(task:to:column.primaryStatus)` without checking whether the task was already in the target column. This meant:

1. For the Done/Abandoned column, `primaryStatus` is always `.done` (by design -- abandoned is never assigned via drag). When an abandoned task was dropped here, it was re-assigned to `.done`.
2. `StatusEngine.applyTransition` always sets `lastStatusChangeDate = now` and, for terminal statuses, `completionDate = now` -- even when the status hasn't actually changed.

**Defect type:** Missing guard -- same-column drops should be no-ops.

**Why it occurred:** The original implementation assumed that drops always represent cross-column moves. The Done/Abandoned column is unique in housing two statuses, making same-column drops a realistic scenario (a user might accidentally drop a task while scrolling, or drag within the column).

**Contributing factors:** Handoff statuses (readyForImplementation, readyForReview) have the same class of issue -- dropping a readyForReview task on the In Progress column would demote it to plain inProgress -- though this is less likely to happen in practice.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/Dashboard/DashboardView.swift` -- Added `DashboardLogic.shouldApplyDrop(task:to:)` that returns `false` when `task.status.column == column`. The `applyDrop` method now calls this guard before delegating to `TaskService.updateStatus`.

**Approach rationale:** Comparing `task.status.column` to the target `column` handles all same-column scenarios in one check: done-on-doneAbandoned, abandoned-on-doneAbandoned, readyForImplementation-on-spec, readyForReview-on-inProgress, and any simple same-status drop. The check is a single line with no risk of side effects.

**Alternatives considered:**
- **Guard on `task.status == column.primaryStatus`** -- Would miss the abandoned-on-doneAbandoned case since `.abandoned != .done`. Also would not protect handoff statuses.
- **Add a no-op guard inside `StatusEngine.applyTransition`** -- StatusEngine is a general-purpose transition engine; silently dropping transitions there could mask bugs in other callers. The guard belongs at the drag-drop level.

## Regression Test

**Test file:** `Transit/TransitTests/DragDropStatusTests.swift`
**Tests added:**
- `abandonedTaskDroppedOnSameColumnStaysAbandoned` -- Verifies an abandoned task keeps its status and timestamps when dropped on Done/Abandoned
- `doneTaskDroppedOnSameColumnPreservesTimestamps` -- Verifies a done task keeps its `completionDate` and `lastStatusChangeDate`
- `sameColumnDropIsNoOp` (parameterized over all statuses) -- Verifies `shouldApplyDrop` returns `false` for every status dropped on its own column
- `handoffStatusPreservedOnSameColumnDrop` -- Verifies readyForImplementation and readyForReview are not demoted
- `crossColumnDropIsApplied` -- Verifies cross-column drops still work

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Dashboard/DashboardView.swift` | Added `shouldApplyDrop` guard in `DashboardLogic.applyDrop` |
| `Transit/TransitTests/DragDropStatusTests.swift` | Added 5 regression tests for same-column drop behavior |

## Verification

**Automated:**
- [x] Regression tests pass
- [x] Full test suite passes
- [x] Linter passes (0 violations)

## Prevention

**Recommendations to avoid similar bugs:**
- When a UI action maps multiple model states to a single visual container (like Done/Abandoned sharing a column), always verify the action is meaningful before applying it.
- Drag-and-drop handlers should treat same-column drops as no-ops at the logic layer, not rely on the view layer to prevent them.
