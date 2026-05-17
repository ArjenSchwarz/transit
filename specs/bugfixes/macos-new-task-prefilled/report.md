# Bugfix Report: macOS New Task Window Prefilled With Previous Values

**Date:** 2026-05-17
**Status:** Fixed

## Description of the Issue

On macOS, after creating a task with the "New Task" window, the next time the
user opens "New Task" (via the toolbar button, the menu, or Cmd+N), the form is
prefilled with the previously entered name, description, type, and milestone
selection instead of starting empty.

**Reproduction steps:**
1. Launch Transit on macOS.
2. Click the "+" toolbar button (or press Cmd+N) to open "New Task".
3. Enter a name (e.g. "Task A"), pick a type, optionally pick a milestone, then
   click Save. The window closes.
4. Click "+" again to open "New Task" a second time.
5. Observe the form still contains "Task A", the previously selected type, and
   the previously selected milestone.

**Impact:** macOS-only UX issue. Confusing for users — looks like the previous
task did not save, and risks accidentally creating duplicate tasks if the user
just clicks Save again.

## Investigation Summary

- **Symptoms examined:** Form fields retain previous values across window
  reopens, but only on macOS. iOS uses a `.sheet(isPresented:)` modifier and is
  not affected.
- **Code inspected:**
  - `Transit/Transit/Views/AddTask/AddTaskSheet.swift` — view's `@State`
    declarations and `.onAppear` handler.
  - `Transit/Transit/TransitApp.swift` — macOS scene definitions
    (`Window("New Task", id: "add-task")`).
  - `Transit/Transit/Views/Dashboard/DashboardView.swift` — `handleAddTask()`
    branches between `openWindow(id: "add-task")` on macOS and
    `showAddTask = true` on iOS.
- **Hypotheses tested:**
  - That `dismiss()` should clear the state — ruled out because `dismiss()` in
    a singleton `Window` scene only closes the window, it does not destroy the
    view.
  - That `.onAppear` does not fire on reopen — ruled out because the existing
    `.onAppear` block already runs to set a default project on first open, so
    it is also entered on subsequent opens.

## Discovered Root Cause

`Window("New Task", id: "add-task")` in `TransitApp.swift` defines a singleton
window scene. Unlike `WindowGroup`, a `Window` is backed by one view instance
for the entire application lifetime. When the user closes the window and
reopens it via `openWindow(id: "add-task")`, SwiftUI reuses that same view —
so `@State` storage (`name`, `taskDescription`, `selectedType`,
`selectedMilestone`, etc.) persists between sessions.

On iOS the same view is presented via `.sheet(isPresented:)`, which creates a
fresh view (and fresh `@State`) on each presentation, so the bug does not
appear.

**Defect type:** Stateful UI lifecycle assumption mismatch between platforms.

**Why it occurred:** When the macOS Window scene was added (so a New Task entry
gets its own window rather than a modal sheet), the author assumed `@State`
would reset on each open the way it does for a sheet. It does not for a
`Window`, and no explicit reset was added.

**Contributing factors:** SwiftUI's `Window` vs `WindowGroup` vs `.sheet`
lifecycle semantics are subtle and not surfaced by the type system; the bug
only manifests on the second-and-subsequent open, which is easy to miss in
ad-hoc testing.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/AddTask/AddTaskSheet.swift` — Added a pure helper
  `AddTaskFormResetLogic` with default form values and a `defaultProjectID`
  selector. Reworked the view's `.onAppear` so that on macOS it resets every
  form field to its default (clearing name, description, type, milestone,
  error message) while still picking a sensible default project. On iOS the
  existing behaviour is preserved (set default project once if not set) since
  the view is freshly constructed on every sheet open.

**Approach rationale:** The minimal correct change is to reset the form when
the singleton macOS view reappears. `.onAppear` already fires on each
reopen — the existing code relies on this for default project selection — so
extending it to do a full reset is low-risk and isolated. Pulling the default
logic into a separate enum keeps it testable without dragging SwiftUI
rendering into unit tests.

**Alternatives considered:**
- Replace `Window` with `WindowGroup` — Rejected because `WindowGroup` would
  let the user open *multiple* New Task windows simultaneously, which is a
  scope change the user didn't ask for and would invite confusion in its own
  right.
- Reset state at the end of `save()` (after a successful create) — Partial fix
  only. Doesn't cover the case where the user types something, closes the
  window without saving, and reopens it later expecting a blank form.

## Regression Test

**Test file:** `Transit/TransitTests/AddTaskSheetResetTests.swift`
**Test name:** `AddTaskSheetResetTests`

**What it verifies:**
- The default form values exposed by `AddTaskFormResetLogic` are empty /
  `.feature` / nil milestone.
- `defaultProjectID(from:current:)` picks the first project when no current
  selection exists, keeps the current selection when it still maps to a known
  project, falls back to the first project when the current selection is
  stale, and returns `nil` when there are no projects at all.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/AddTask/AddTaskSheet.swift` | Added `AddTaskFormResetLogic` helper and macOS-specific `.onAppear` reset. |
| `Transit/TransitTests/AddTaskSheetResetTests.swift` | New regression test suite (T-825). |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

**Manual verification:**
- Open Transit on macOS, create a task via the "+" button, then click "+"
  again. Confirm the form is empty.

## Prevention

**Recommendations to avoid similar bugs:**
- Treat singleton `Window` scenes on macOS as long-lived view instances; any
  form they host should reset its `@State` on `.onAppear` (or be modelled with
  an observable form-state object that is explicitly reset on entry).
- When mirroring an iOS sheet to a macOS window, audit any reliance on
  per-presentation `@State` reset semantics — they don't carry over from
  sheets to `Window`.

## Related

- Transit ticket T-825
- `docs/agent-notes/stream2-ui-views.md` (AddTaskSheet section)
