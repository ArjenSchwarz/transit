# Bugfix Report: Add Task Stale Terminal Milestone

**Date:** 2026-08-04
**Status:** Fixed

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

**Changes made:**
- `Transit/Transit/Services/TaskCreationMilestoneValidator.swift` — reads the selected milestone from the live context and a fresh transient context, requiring every available view to remain open and project-matched.
- `Transit/Transit/Services/TaskService.swift` — calls that validation after the display-ID allocation await and cancellation re-check, immediately before constructing and inserting the task.
- `Transit/Transit/Views/AddTask/AddTaskSheet.swift` — observes the selected project's milestone records and clears a selection as soon as it leaves the open option set, so the picker and draft do not retain a terminal selection.
- `Transit/Transit/Services/TaskService+Error.swift` — adds the localized `milestoneNotOpen` error surfaced by Add Task.
- `Transit/Transit/Intents/CreateTaskIntent.swift` — maps the new service error to `INVALID_INPUT` rather than an internal failure.
- `Transit/Transit/MCP/MCPToolHandler.swift` — returns the localized terminal-milestone message rather than an enum case name from `create_task`.

**Approach rationale:** The guard sits after the last suspension point and before `TransitTask` construction, closing the status-change race without relying on picker refreshes or `onChange`. It combines live state (including local pending updates) with a fresh committed-store read (including peer/window updates), and rejects before `insertOrDelete`, preserving the existing atomic one-save task/milestone path.

**Alternatives considered:**
- Clearing `selectedMilestone` only when the picker options change — rejected because it misses a closure that occurs after selection or during awaited task creation, and does not protect non-UI callers.
- Changing the dashboard terminal filter — rejected because T-1825 is separate behavior and remains unchanged.

## Regression Test

**Test file:** `Transit/TransitTests/AddTaskStaleMilestoneTests.swift`
**Test name:** `persistRejectsMilestoneClosedAfterSelectionBeforeSaveWithoutInsertingTask`

**What it verifies:** A gated display-ID allocation permits a peer context to change a formerly selected milestone to Done or Abandoned deterministically. The Add Task persistence path must reject the stale selection with `milestoneNotOpen` and leave no pending or committed task.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|---|---|
| `Transit/Transit/Services/TaskCreationMilestoneValidator.swift` | Validates project scope and open status against live and committed milestone state. |
| `Transit/Transit/Services/TaskService.swift` | Applies validation after allocation and before task construction/insertion. |
| `Transit/Transit/Services/TaskService+Error.swift` | Adds localized terminal/unavailable milestone rejection. |
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Maps rejection to `INVALID_INPUT`. |
| `Transit/TransitTests/AddTaskStaleMilestoneTests.swift` | Covers deterministic peer-context Done/Abandoned closure with no partial task. |

## Verification

**Automated:**
- [x] Focused regression passes for Done and Abandoned (`AddTaskStaleMilestoneTests`)
- [x] macOS unit suite passes (`make test-quick`)
- [x] Strict lint passes (`make lint`)
- [ ] iOS suite (`make test`) did not complete: two attempts timed out after building and beginning tests; Xcode logged repeated LLDB debugger-version-store failures.
- [ ] UI suite (`make test-ui`) not run after the full iOS suite could not complete in this environment.

**Manual verification:**
- The deterministic two-context test models the Add Task selection, external closure, and save boundary directly; no manual UI run was performed.

## Prevention

- Validate mutable relationship invariants at the final persistence boundary, not only while collecting UI state.
- Combine a transient committed-store read with live context state when a selected SwiftData model may be stale after a cross-window or CloudKit update.

## Related

- T-2037
- T-1825 (separate dashboard terminal-filter behavior; intentionally unchanged)
