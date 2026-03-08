# Keyboard Shortcut for New Task

## Overview

The kanban dashboard has no keyboard shortcuts. Users must click the "+" toolbar button to create a new task. This change adds two keyboard shortcuts to open the Add Task sheet from the dashboard: Cmd+N (standard macOS/iPadOS shortcut) and the bare "t" key (quick access without modifier). Both trigger the same `showAddTask` state that the existing toolbar button uses.

## Requirements

- The system MUST open the Add Task sheet when the user presses Cmd+N while the dashboard is visible
- The system MUST open the Add Task sheet when the user presses the "t" key (no modifier) while the dashboard is visible and no text field has focus
- The system MUST NOT trigger the "t" shortcut when the search bar or any other text input has focus
- The system MUST NOT trigger either shortcut when the Add Task sheet or task detail sheet is already presented
- The system SHOULD use `.keyboardShortcut("n", modifiers: .command)` on the existing toolbar button for Cmd+N
- The system SHOULD use `.onKeyPress` on the dashboard body for the bare "t" key shortcut

## Implementation Approach

- **Add `.keyboardShortcut("n", modifiers: .command)`** to the `addButton` computed property in `Transit/Transit/Views/Dashboard/DashboardView.swift` (line 161-168) on iOS only (`#if !os(macOS)`). On macOS, Cmd+N is handled by the `CommandGroup` instead to avoid conflict.
- **Add `.focusable()` and `.onKeyPress` modifiers** to the `body` of `DashboardView`, after the `.sheet(isPresented: $showAddTask)` modifier (around line 123). `.focusable()` is required so the dashboard can receive key events when no text field has focus. The handler checks `!showAddTask && selectedTask == nil` to avoid triggering while any sheet is open, then sets `showAddTask = true` and returns `.handled`. Returns `.ignored` otherwise to let the event propagate.
- The "t" key shortcut uses `.onKeyPress("t")` which only fires when the dashboard view tree has key focus. When `.searchable`'s text field is focused, key events are consumed by the text field and do not propagate to `.onKeyPress` — no additional guard is needed.
- **Add a `FocusedShowAddTask` focused value key** in a new file or alongside DashboardView, exposing a `Binding<Bool>` for `showAddTask`. DashboardView publishes via `.focusedValue(\.showAddTask, $showAddTask)`.
- **Add `CommandGroup(replacing: .newItem)`** to the `WindowGroup` scene in `Transit/Transit/TransitApp.swift` (around line 139), wrapped in `#if os(macOS)`. The command reads `@FocusedBinding(\.showAddTask)` and sets it to `true`. This places "New Task" with Cmd+N in the macOS File menu, replacing the default "New Window" item.

**Existing patterns to follow:**
- Toolbar button: `addButton` at `DashboardView.swift:161-168` already toggles `showAddTask`
- Sheet presentation: `.sheet(isPresented: $showAddTask)` at line 121-123
- Accessibility identifiers: toolbar buttons use `accessibilityIdentifier("dashboard.xxx")` pattern
- `#if os(macOS)` guards: used in both `DashboardView.swift:84` and `TransitApp.swift:87-95`

**Dependencies:**
- `showAddTask` `@State` property (DashboardView.swift:13) — controls sheet presentation
- `AddTaskSheet` view — presented by the sheet modifier, unchanged
- SwiftUI `FocusedValueKey` protocol — for communicating between `CommandGroup` and `DashboardView`

**Out of Scope:**
- Configurable keyboard shortcuts
- Keyboard shortcuts for other actions (navigation, filters, etc.)

## Risks and Assumptions

- **Risk:** `.onKeyPress` for bare "t" could interfere with system key handling or accessibility features | **Mitigation:** Return `.handled` only when the shortcut is consumed; return `.ignored` when any sheet is already open, letting the event propagate normally
- **Risk:** On macOS, `CommandGroup(replacing: .newItem)` removes the default "New Window" menu item | **Mitigation:** Transit is a single-window app; replacing with "New Task" is consistent with how single-window macOS apps use Cmd+N for their primary "new item" action
- **Risk:** `.onKeyPress` requires the view to have keyboard focus; after dismissing a sheet, focus may not return to the dashboard | **Mitigation:** Add `.focusable()` to the dashboard so it can accept key focus; SwiftUI restores focus to the previously focused view after sheet dismissal
- **Assumption:** SwiftUI's `.searchable` text field consumes key events when focused, preventing `.onKeyPress` on the parent view from firing — this is standard SwiftUI focus/responder behavior
- **Assumption:** `.onKeyPress` is available on both iOS 26 and macOS 26 (introduced in iOS 17 / macOS 14)
