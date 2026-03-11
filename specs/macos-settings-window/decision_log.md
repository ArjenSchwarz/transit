# Decision Log: macOS Settings Window

## Decision 1: Use SwiftUI `Settings` Scene Over Custom `Window` Scene

**Date**: 2026-03-11
**Status**: accepted

### Context

Transit needs to present settings in a separate macOS window instead of pushing it onto the main NavigationStack. SwiftUI offers two approaches: the built-in `Settings` scene (purpose-built for preferences) and a custom `Window(id:)` scene (general-purpose secondary window).

### Decision

Use SwiftUI's `Settings` scene for the macOS settings window.

### Rationale

The `Settings` scene is the idiomatic SwiftUI approach for macOS preferences. It automatically provides Cmd+Comma keyboard shortcut, a "Settings..." menu item in the app menu, standard window chrome, and correct window behavior (non-restorable, single instance). A custom `Window` scene would require manually implementing all of these conventions.

### Alternatives Considered

- **`Window(id: "settings")` with `openWindow`**: Full control over window behavior and size — Rejected because it requires manually implementing keyboard shortcut, menu item, and window management that `Settings` scene provides for free. May be used as a fallback if `NavigationStack` doesn't work well inside `Settings` scene.
- **Keep NavigationStack push (status quo)**: No code changes needed — Rejected because it violates macOS conventions and prevents the settings window from being positioned independently of the main window.

### Consequences

**Positive:**
- Automatic Cmd+Comma and menu item support
- Standard macOS preferences window behavior
- Minimal code required

**Negative:**
- Less control over window size and behavior compared to `Window` scene
- `NavigationStack` inside `Settings` scene needs runtime verification
- If push navigation doesn't work, requires fallback to `Window` scene approach

---
