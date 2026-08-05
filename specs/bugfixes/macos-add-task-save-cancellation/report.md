# Bugfix Report: macOS Add Task Save Cancellation

**Date:** 2026-08-05
**Status:** Fixed

## Description of the Issue

On macOS, the singleton **New Task** window launched an unretained asynchronous `Task` when Save was pressed. If the window closed while display-ID allocation was suspended, the task could continue and persist a new task after the user dismissed the window.

**Reproduction steps:**
1. Open New Task on macOS and enter a valid task.
2. Press Save while display-ID allocation is delayed.
3. Close the New Task window before allocation completes.
4. Release allocation and observe that the task can be inserted after the window closed.

**Impact:** A user could create an unintended task by closing the creation window during a slow allocation.

## Investigation Summary

- **Symptoms examined:** The `Task { await save() }` launched by the Add Task toolbar was not stored or cancelled on disappearance.
- **Code inspected:** `AddTaskSheet.swift`, `AddTaskSheet+Save.swift`, `TaskService.swift`, `DisplayIDAllocator.swift`, and T-1858's milestone create lifecycle.
- **Hypotheses tested:** `TaskService` might persist despite cancellation. It already propagates `CancellationError` and checks cancellation immediately before insertion (T-1765); the missing layer was the Add Task view lifecycle.

## Discovered Root Cause

The macOS Add Task view had no retained save-task handle or state transition for window disappearance. Closing the view therefore did not deliver cancellation to the in-flight `Task`; service safeguards only take effect once its caller is cancelled.

**Defect type:** Lifecycle management / asynchronous cancellation gap.

**Why it occurred:**
1. Save created an unretained task.
2. The view had no `onDisappear` cancellation path.
3. Slow display-ID allocation permitted the window to close first.
4. The still-running task completed allocation and called the create service.
5. The service correctly observed no cancellation and inserted the task.

**Contributing factors:** iOS already disables interactive dismissal while saving, but the macOS singleton window had no equivalent lifecycle handling. T-1858 introduced the required state machine for milestone creation, but Add Task did not use it.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/AddTask/AddTaskSheet.swift` — retains the save task and shared lifecycle, disables existing iOS dismissal affordances from lifecycle state, cancels a pending save on disappearance, and resets the singleton window only after a successful dismissal.
- `Transit/Transit/Views/AddTask/AddTaskSheet+Save.swift` — starts one retained task, completes success before dismissal, suppresses `CancellationError` alerts, and restores error/retry behavior for genuine failures.
- `Transit/Transit/Views/Shared/CreateSaveLifecycle.swift` — generalizes T-1858's lifecycle state machine and adds success-only reset support for reusable windows.
- `Transit/Transit/Views/Settings/MilestoneCreateSaveLifecycle.swift` — retains the existing milestone name as a compatibility alias.
- `Transit/TransitTests/AddTaskSaveLifecycleTests.swift` — adds deterministic lifecycle and gated-allocation regressions.

**Approach rationale:** The view now owns the operation that its lifecycle can invalidate, while `TaskService` remains the persistence boundary that prevents an already-cancelled allocation from inserting. This preserves T-2037's milestone validation and existing create-service cancellation behavior.

**Alternatives considered:**
- Cancel only on macOS without explicit save state — rejected because a successful `dismiss()` would race its own `onDisappear` and could be incorrectly treated as a failure.
- Add compensating deletion after cancellation — rejected because cancellation before the service insertion boundary is atomic and avoids deleting a successfully persisted task.

## Regression Test

**Test file:** `Transit/TransitTests/AddTaskSaveLifecycleTests.swift`

**What it verifies:** A deterministic `AllocationGatedCounterStore` test cancels while display-ID allocation is suspended and proves `CancellationError` plus zero persisted tasks. Companion lifecycle tests prove successful dismissal is not cancelled and a genuine failure reenables retry.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/AddTask/AddTaskSheet.swift` | Retained save ownership and disappearance cancellation. |
| `Transit/Transit/Views/AddTask/AddTaskSheet+Save.swift` | Lifecycle-aware save outcomes and silent cancellation handling. |
| `Transit/Transit/Views/Shared/CreateSaveLifecycle.swift` | Shared creation lifecycle helper. |
| `Transit/Transit/Views/Settings/MilestoneCreateSaveLifecycle.swift` | T-1858 compatibility alias. |
| `Transit/TransitTests/AddTaskSaveLifecycleTests.swift` | Deterministic regressions. |
| `CHANGELOG.md` | T-1898 release note. |

## Verification

**Automated:**
- [x] Focused `AddTaskSaveLifecycleTests` passes on macOS.
- [x] `make test-quick` passes.
- [x] `make build-macos` passes.
- [x] `make lint` passes.

**Manual verification:** Not run; the deterministic gated allocator regression simulates closing New Task during the exact allocation suspension window.

## Prevention

Creation views that can disappear during asynchronous persistence must retain the task and use an explicit lifecycle state machine. Successful persistence must transition before `dismiss()` so its own disappearance cannot cancel it.

## Related

- T-1898
- T-1858
- T-1765
- T-2037
