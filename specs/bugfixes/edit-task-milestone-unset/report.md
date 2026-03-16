# Bugfix Report: Edit Task Milestone Unset

**Date:** 2025-07-16
**Status:** Fixed

## Description of the Issue

When opening the edit view for a task that has a milestone assigned, the milestone picker shows "None" instead of the task's actual milestone. If the user saves without manually re-selecting the milestone, the assignment is silently cleared.

**Reproduction steps:**
1. Create a task with a milestone assigned (e.g., "Ship Active" with milestone "v1.0")
2. Tap the task card to open the detail view
3. Tap the pencil icon to open the edit view
4. Observe: the Milestone picker shows "None" instead of "v1.0"

**Impact:** Medium — milestone assignments are silently lost when editing any other task property.

## Investigation Summary

- **Symptoms examined:** Milestone picker always shows "None" in the edit view, regardless of task's actual milestone
- **Code inspected:** `TaskEditView.swift` (state initialization, `loadTask()`, `.onChange` handlers, Picker bindings)
- **Hypotheses tested:**
  - SwiftData object reference mismatch in Picker tags — ruled out (same ModelContext identity map)
  - `.onChange(of: selectedProjectID)` firing during initial load — **confirmed as root cause**

## Discovered Root Cause

**Defect type:** State management / lifecycle ordering error

The `.onChange(of: selectedProjectID)` modifier unconditionally clears `selectedMilestone` to `nil` whenever `selectedProjectID` changes. This is correct when the user actively switches projects (milestone should be cleared since it belongs to the old project). However, it also fires during the initial `loadTask()` call when `selectedProjectID` changes from its default `nil` to the task's project UUID.

**Sequence of events:**
1. `TaskEditView` initializes with `@State selectedProjectID: UUID? = nil` and `@State selectedMilestone: Milestone? = nil`
2. `.onAppear` calls `loadTask()`, which sets `selectedProjectID = task.project?.id` and `selectedMilestone = task.milestone`
3. SwiftUI batches the state updates and re-renders
4. `.onChange(of: selectedProjectID)` fires because the value changed from `nil` to a UUID
5. The handler sets `selectedMilestone = nil`, **overwriting** the milestone that `loadTask()` just set

**Why it occurred:** The `.onChange` handler didn't distinguish between initial population and user-initiated project changes.

**Contributing factors:** SwiftUI's `.onChange` fires after any state change, including programmatic ones during `onAppear`. This is a common SwiftUI pitfall.

## Resolution for the Issue

**Changes made:**
- `Transit/Views/TaskDetail/TaskEditView.swift:114` (iOS) — Guard `.onChange` handler to only fire when `oldValue != nil`
- `Transit/Views/TaskDetail/TaskEditView.swift:202` (macOS) — Same guard applied

**Approach rationale:** By checking `oldValue != nil`, we distinguish between:
- **Initial load** (`nil` → project UUID): don't clear milestone — `loadTask()` already set it correctly
- **User changes project** (UUID → different UUID): clear milestone — it belongs to the old project

**Alternatives considered:**
- Using a `@State private var isLoading` flag to skip `.onChange` during initial load — more complex, same result
- Reordering `loadTask()` to set milestone after project ID with a `Task` delay — fragile, timing-dependent

## Regression Test

**Test file:** `Transit/TransitUITests/TransitUITests.swift`
**Test name:** `testEditViewPreservesTaskMilestone`

**What it verifies:** Opens the edit view for a task with milestone "v1.0" and asserts the milestone picker shows "v1.0" (not "None").

**Run command:** `make test-ui`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Views/TaskDetail/TaskEditView.swift` | Guard `.onChange(of: selectedProjectID)` to skip initial load (both iOS and macOS) |
| `Transit/TransitUITests/TransitUITests.swift` | Add regression test `testEditViewPreservesTaskMilestone` |

## Verification

**Automated:**
- [x] Regression test written
- [x] Unit test suite passes (`make test-quick`)
- [x] Linter passes (`make lint`)

## Prevention

**Recommendations to avoid similar bugs:**
- When using `.onChange` in SwiftUI edit views that populate state via `.onAppear`/`loadTask()`, always check `oldValue` to distinguish initial load from user interaction
- Consider extracting form state into an `@Observable` view model where lifecycle can be controlled more explicitly
- Add UI tests for edit views that verify pre-populated state is preserved on load

## Related

- T-415: Fix for closed milestones being hidden in edit view (related but different root cause)
- Commit 8ffe3ce: Prior milestone picker fix that added `availableMilestones` logic
