# Implementation Explanation: Keyboard Shortcut for New Task (T-36)

## Beginner Level

### What Changed
Transit's kanban dashboard now lets you create a new task using keyboard shortcuts instead of clicking the "+" button. Two shortcuts were added:

- **Cmd+N** — the standard "new item" shortcut that most apps use
- **t** (just the letter, no modifier) — a quick shortcut for power users who want fast access

Both shortcuts open the same "Add Task" form that the toolbar button already opens.

### Why It Matters
Keyboard shortcuts make the app faster to use, especially on iPad with a hardware keyboard and on Mac. Users who manage many tasks can create new ones without moving their hands from the keyboard to the mouse/trackpad.

### Key Concepts
- **Keyboard shortcut**: A key combination that triggers an action without clicking a button
- **Sheet**: A panel that slides up (iOS) or appears as a modal (macOS) to show a form
- **Focus**: Which part of the app is currently receiving keyboard input — when you're typing in the search bar, that has focus, so pressing "t" types the letter instead of opening the form

---

## Intermediate Level

### Changes Overview
Three files modified, one test file added:

| File | Change |
|------|--------|
| `DashboardView.swift` | Added `.keyboardShortcut` on toolbar button (iOS), `.focusable()` + `.onKeyPress("t")` for bare key, `FocusedValueKey` wiring, guard logic in `DashboardLogic` |
| `TransitApp.swift` | Added `NewTaskCommand` (`CommandGroup(replacing: .newItem)`) for macOS File menu |
| `CHANGELOG.md` | Documented the new shortcuts |
| `DashboardShortcutTests.swift` | Unit tests for the guard logic |

### Implementation Approach

**Cmd+N is split by platform:**
- iOS/iPadOS: `.keyboardShortcut("n", modifiers: .command)` directly on the existing `addButton` toolbar button. SwiftUI handles the rest.
- macOS: A `CommandGroup(replacing: .newItem)` in `TransitApp.swift` places "New Task" in the File menu. This replaces the default "New Window" item (appropriate for a single-window app). The command reads the dashboard's `showAddTask` state via SwiftUI's `FocusedValue` system.

**The split is necessary** because macOS toolbar `.keyboardShortcut` and `CommandGroup` both respond to Cmd+N, creating a conflict. The `#if os(macOS)` / `#if !os(macOS)` guards ensure each platform uses the appropriate mechanism.

**Bare "t" key** uses `.onKeyPress("t")` on the DashboardView body. The view must be `.focusable()` to receive key events. The handler delegates to `DashboardLogic.shouldHandleNewTaskShortcut()` — a pure function that returns `true` only when no sheet is currently open (`showAddTask == false && selectedTask == nil`).

**Communication between DashboardView and NewTaskCommand** uses SwiftUI's `FocusedValueKey` pattern:
- `FocusedShowAddTask` publishes a `Binding<Bool>` so the command can write `showAddTask = true`
- `FocusedIsTaskSelected` publishes a read-only `Bool` so the command knows whether the task detail sheet is open

### Trade-offs
- **Extracted guard logic vs inline**: The `shouldHandleNewTaskShortcut` check could live inline in the `.onKeyPress` closure. Extracting it to `DashboardLogic` enables unit testing without UI test infrastructure.
- **Two FocusedValueKeys vs one combined flag**: Publishing both `showAddTask` and `isTaskSelected` separately (rather than a single "anySheetOpen" boolean) is slightly more verbose but keeps the binding for `showAddTask` writable — the command needs to *set* it, not just read it.

---

## Expert Level

### Technical Deep Dive

**Focus chain and event propagation:**
`.onKeyPress("t")` only fires when the DashboardView's subtree has keyboard focus. When `.searchable`'s text field is focused, it's a separate responder that consumes key events before they reach `.onKeyPress` — no explicit guard is needed for the search bar case. The guard in `shouldHandleNewTaskShortcut` handles the sheet-already-open cases.

**macOS command disabled state:**
```swift
.disabled(showAddTask != false || isTaskSelected == true)
```
`showAddTask` is `Optional<Bool>` (from `@FocusedBinding`). Three states: `nil` (no dashboard visible — disable), `true` (sheet open — disable), `false` (ready — enable). The condition `showAddTask != false` collapses nil and true into "disabled". `isTaskSelected == true` adds the task detail sheet guard. This matches the bare "t" key's guard logic, ensuring consistent behavior across both shortcut paths.

**`.focusable()` implications:**
Adding `.focusable()` to DashboardView means it participates in the focus system. On macOS, this could show a focus ring; on iOS, it enables `.onKeyPress` to receive events. SwiftUI restores focus to the previously focused view after sheet dismissal, so the "t" key continues to work after closing the Add Task sheet.

### Architecture Impact
- **FocusedValueKey pattern**: This is the first usage in the codebase. It establishes the pattern for future scene-level communication (e.g., if other menu commands need to read dashboard state).
- **DashboardLogic expansion**: The `shouldHandleNewTaskShortcut` method follows the existing `shouldApplyDrop` pattern — pure static functions on `DashboardLogic` for testable UI predicates.
- **No new state**: Both shortcuts reuse the existing `showAddTask` `@State` property. No new view state or service dependencies were introduced.

### Potential Issues
- **Focus restoration after sheet dismissal**: SwiftUI should restore focus to the dashboard after a sheet is dismissed, but this is framework-dependent behavior. If focus doesn't return, the "t" key won't work until the user clicks/taps the dashboard area.
- **`.focusable()` on macOS may show a focus ring**: This is a cosmetic concern; the focus ring appears when the dashboard receives focus via Tab navigation. It may need `.focusEffectDisabled()` if it's visually distracting.
- **Concurrent sheets**: SwiftUI does not present two `.sheet` modifiers simultaneously. If Cmd+N fires while the task detail sheet is open (which should be prevented by the disabled check), `showAddTask` would be set to `true` but the sheet might not appear, leaving state inconsistent. The `isTaskSelected` guard prevents this.

---

## Completeness Assessment

### Fully Implemented
- Cmd+N opens Add Task sheet on iOS/iPadOS (via `.keyboardShortcut`)
- Cmd+N opens Add Task sheet on macOS (via `CommandGroup` in File menu)
- Bare "t" key opens Add Task sheet with guard conditions
- Guard prevents shortcuts when any sheet is already open
- Search bar focus naturally prevents "t" key interference
- Unit tests cover all guard condition combinations

### Not Applicable / Out of Scope
- Configurable keyboard shortcuts (explicitly out of scope per spec)
- Keyboard shortcuts for other actions (explicitly out of scope per spec)
- UI tests for keyboard shortcuts (difficult to test `.onKeyPress` and `.keyboardShortcut` in XCUITest; guard logic is covered by unit tests)
