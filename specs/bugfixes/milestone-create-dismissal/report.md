# Bugfix Report: Milestone Create Dismissal

**Date:** 2026-08-05
**Status:** Investigating

## Description of the Issue

`MilestoneEditView` starts create-mode persistence in an unretained `Task`. While display-ID allocation is awaiting, the iOS back control remains available and macOS navigation can replace the editor. The view disappears but the operation continues, eventually persisting a milestone that the user had cancelled.

**Reproduction steps:**
1. Open **New Milestone** and enter a valid name.
2. Tap Save while display-ID allocation is slow or offline.
3. Navigate back on iOS, or change the Settings category on macOS.
4. Wait for allocation to finish.
5. Observe that the milestone is persisted despite the editor having been dismissed.

**Impact:** A cancellation can create an unexpected milestone. The risk is highest when CloudKit display-ID allocation suspends for a noticeable time.

## Investigation Summary

### Phase 1 — Initial overview

Expected behavior: the create operation either completes while the editor remains active, or a true view disappearance cancels the pending operation before persistence.

Actual behavior: the create task outlives the editor. The UI does not represent a cancellation boundary for the async create.

### Phase 2 — Systematic inspection

- `Transit/Transit/Views/Settings/MilestoneEditView.swift` creates an unstructured `Task` and does not retain it.
- The iOS custom back button is not disabled while `isSaving` is true; sheet-style interactive dismissal is also not blocked.
- No `onDisappear` lifecycle hook cancels an in-flight create, so macOS Settings-category navigation can also orphan the operation.
- `Transit/Transit/Services/MilestoneService.swift` already preserves the T-1765 invariant: after the allocation await it calls `Task.checkCancellation()` before constructing or saving a `Milestone`.
- Edit mode is synchronous and uses merge/conflict behavior; it must remain unchanged.

### Phase 3 — Root cause analysis

1. Why does dismissal persist a milestone? The create task continues after the view disappears.
2. Why does it continue? The view does not retain the task or cancel it on disappearance.
3. Why can the view disappear during save? The iOS back control remains enabled, and macOS navigation can replace the detail stack.
4. Why would cancellation be safe? T-1765 checks cancellation after allocation and immediately before the persistence boundary.
5. Root cause: `MilestoneEditView` has no explicit state machine separating an in-flight save from a successfully completed save that is about to dismiss.

**Defect type:** Async lifecycle race / missing cancellation boundary.

**Assumption validated:** The T-1765 service guard is after the only suspension in `createMilestone` and before insertion, so cancellation while allocation is pending cannot persist a milestone.

## Resolution for the Issue

Pending implementation.

**Proposed approach:** Add a small testable create-save lifecycle helper. Retain the create `Task`, block iOS dismissal while saving, cancel the retained task only when a still-pending create disappears, and transition to a successful-completion state before calling `dismiss()` so success does not cancel itself.

**Alternatives considered:**
- Disable only the iOS back button — rejected because it does not cover swipe navigation or macOS category/detail replacement.
- Cancel every operation from `onDisappear` — rejected because a completed save’s `dismiss()` would spuriously cancel its own task.
- Change `MilestoneService` persistence behavior — rejected because T-1765 already provides the necessary cancellation check and the defect is view lifecycle ownership.

## Regression Test

**Test file:** `Transit/TransitTests/MilestoneCreateSaveLifecycleTests.swift`

**Test names:** lifecycle tests covering in-flight disappearance, successful-save dismissal, failure retry, and cancellation completion.

**What they verify:** The view-state model requests cancellation only for a genuinely pending create and keeps successful dismissal distinct from cancellation.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Settings/MilestoneEditView.swift` | Retain/cancel create task and gate iOS dismissal. |
| `Transit/Transit/Views/Settings/MilestoneCreateSaveLifecycle.swift` | Testable create-save lifecycle state helper. |
| `Transit/TransitTests/MilestoneCreateSaveLifecycleTests.swift` | Lifecycle regressions for T-1858. |

## Verification

**Automated:**
- [ ] Regression lifecycle tests pass.
- [ ] T-1765 cancelled-create service tests pass.
- [ ] `make test-quick` passes.
- [ ] `make lint` passes.

**Manual verification:**
- [ ] iOS: Save a new milestone during delayed allocation; back and interactive dismissal remain unavailable.
- [ ] macOS: Navigate away while saving; the operation is cancelled and no milestone appears.
- [ ] Successful create still dismisses the editor; edit-mode save/error behavior is unchanged.

## Prevention

- Async view-owned persistence must retain its task and give disappearance a deliberate cancellation policy.
- Represent “save completed and now dismissing” separately from “save in progress” so lifecycle hooks cannot cancel successful work.
- Keep cancellation checks at service persistence boundaries for non-cooperative external awaits (T-1765).

## Related

- T-1858 — Milestone creation continues after the editor is dismissed.
- T-1765 — Pre-cancelled creates can still persist records.
- `Transit/Transit/Views/AddTask/AddTaskSheet.swift` — existing iOS save-dismissal guard pattern.
