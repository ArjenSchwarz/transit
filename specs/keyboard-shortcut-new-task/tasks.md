---
references:
    - specs/keyboard-shortcut-new-task/smolspec.md
---
# Keyboard Shortcut for New Task

- [ ] 1. Cmd+N opens Add Task sheet on iOS/iPadOS via `.keyboardShortcut` on the existing toolbar button
  - Add `.keyboardShortcut("n", modifiers: .command)` to `addButton` in DashboardView.swift, wrapped in `#if !os(macOS)`.
  - Verify Cmd+N opens the Add Task sheet on iOS Simulator with hardware keyboard.

- [ ] 2. FocusedValueKey wiring exposes `showAddTask` binding to the scene level <!-- id:0mr895z -->
  - Define a `FocusedShowAddTask` key conforming to `FocusedValueKey` with `Value = Binding<Bool>`.
  - Publish `.focusedValue(\.showAddTask, $showAddTask)` from DashboardView.
  - Verify the focused value is accessible from a CommandGroup.

- [ ] 3. macOS File menu shows "New Task" (Cmd+N) via CommandGroup replacing .newItem <!-- id:0mr8960 -->
  - Add `CommandGroup(replacing: .newItem)` to the WindowGroup in TransitApp.swift, wrapped in `#if os(macOS)`.
  - Read `@FocusedBinding(\.showAddTask)` and set to true.
  - Verify "New Task" appears in the File menu and Cmd+N opens the sheet.
  - Blocked-by: 0mr895z (FocusedValueKey wiring exposes `showAddTask` binding to the scene level)

- [ ] 4. Bare "t" key opens Add Task sheet when dashboard has focus and no sheet is presented <!-- id:0mr8961 -->
  - Add `.focusable()` and `.onKeyPress("t")` to DashboardView body.
  - Guard on `!showAddTask && selectedTask == nil` — return `.handled` when consumed, `.ignored` otherwise.
  - Verify: pressing t opens the sheet, pressing t while search bar is focused types "t" instead, pressing t while detail sheet is open does nothing.

- [ ] 5. Unit tests verify shortcut guard conditions <!-- id:0mr8962 -->
  - Add tests confirming: guard returns false when showAddTask is true, guard returns false when selectedTask is non-nil, guard returns true when both are false/nil.
  - If guard logic is inline in the view, extract to a static helper on DashboardLogic for testability.
  - Blocked-by: 0mr8961 (Bare "t" key opens Add Task sheet when dashboard has focus and no sheet is presented)

- [ ] 6. Build succeeds on both iOS and macOS targets with no warnings
  - Run `make build` and `make lint`.
  - Fix any compiler warnings or lint issues introduced by the changes.
  - Verify no regressions in existing functionality.
