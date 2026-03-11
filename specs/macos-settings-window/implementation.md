# Implementation Explanation: macOS Settings Window (T-51)

## Beginner Level

### What Changed
Transit's settings screen on macOS now opens in its own separate window instead of sliding in from the right side of the main app window. On iOS (iPhone/iPad), nothing changed — settings still works the same way.

### Why It Matters
Mac apps have a long-standing convention: pressing Cmd+Comma (or clicking "Settings..." in the app menu) opens a dedicated preferences window. Before this change, Transit treated settings like any other screen — it pushed it onto the same window as the dashboard, which felt wrong on macOS. Users couldn't position the settings window independently or keep it open alongside the dashboard.

### Key Concepts
- **Scene**: In SwiftUI, a "scene" is a top-level container that manages a window. The app's main dashboard is one scene (`WindowGroup`), and the new settings window is another scene (`Settings`).
- **Settings scene**: A special SwiftUI scene type built specifically for macOS preferences. It automatically provides the Cmd+Comma shortcut and the "Settings..." menu item.
- **SettingsLink**: A SwiftUI view (like a button) that, when tapped, opens the Settings scene window.
- **NavigationStack**: The mechanism that lets you push and pop screens within a single window. The settings window has its own NavigationStack so you can drill into sub-screens (like editing a project) without leaving the settings window.

---

## Intermediate Level

### Changes Overview
Three production files were modified:

| File | Change |
|------|--------|
| `TransitApp.swift` | Added a `Settings` scene (macOS only) with its own `NavigationStack`, `navigationDestination` handler, environment injection, and model container |
| `DashboardView.swift` | Replaced `NavigationLink` with `SettingsLink` on macOS via `#if os(macOS)` |
| `SettingsView.swift` | Removed `.navigationBarBackButtonHidden(true)` and `.toolbar { settingsToolbar }` from macOS path — no longer needed since settings is the root of its own window |

### Implementation Approach
The implementation follows SwiftUI's built-in `Settings` scene pattern rather than using a custom `Window(id:)` scene. This is idiomatic and gives automatic Cmd+Comma, menu item, and standard window chrome for free.

The Settings scene mirrors the WindowGroup's setup:
- Same `NavigationStack` with `navigationDestination(for: NavigationDestination.self)` for sub-navigation
- Same environment objects injected (services, theme, MCP)
- Same `.modelContainer` and `.preferredColorScheme`

Two `NavigationDestination` cases (`.settings` and `.report`) render `EmptyView()` in the Settings scene since they're unreachable there but required for exhaustive switch coverage.

Platform branching uses `#if os(macOS)` consistently — the same pattern already used throughout the codebase for platform-specific UI.

### Trade-offs
- **`Settings` scene vs `Window(id:)` scene**: `Settings` was chosen for automatic macOS conventions (keyboard shortcut, menu item, single-instance behavior). The trade-off is less control over window sizing — documented as an acceptable risk with a fallback plan.
- **Duplicated environment injection**: The environment modifiers are repeated across both scenes. This is structurally required by SwiftUI (each scene needs its own environment chain) and there are only two call sites, keeping it inline rather than extracting a ViewModifier.
- **Removing back button globally vs conditionally**: The `.navigationBarBackButtonHidden` and custom toolbar were removed from the macOS settings path entirely. iOS retains its own back button setup in the `iOSSettings` computed property.

---

## Expert Level

### Technical Deep Dive
The `Settings` scene is a peer to the `WindowGroup` in the `App.body` scene builder. SwiftUI creates a separate window hierarchy for it, meaning:

- `@Query` results work because `.modelContainer(container)` shares the same container instance
- `@AppStorage` changes propagate immediately across windows since UserDefaults is process-global
- `@Environment` values must be explicitly re-injected — they don't inherit from the WindowGroup

The `navigationDestination` handler in the Settings scene handles all six `NavigationDestination` cases exhaustively. Two cases (`.settings`, `.report`) return `EmptyView()` because they're unreachable from within the settings window but Swift requires exhaustive switching. This is correct — the enum is shared across iOS and macOS, and adding platform-specific cases would be worse.

The `SettingsLink` in DashboardView's toolbar is wrapped in `#if os(macOS)` at compile time rather than using runtime `#available` checks, since the `Settings` scene itself is macOS-only and `SettingsLink` doesn't exist on iOS.

### Architecture Impact
This change introduces a second scene in the app, which has implications:
- `ScenePhaseModifier` (display ID promotion) is only attached to the WindowGroup, not the Settings scene — this is correct since promotion should only trigger on main app lifecycle events
- The `.task { startMCPServerIfEnabled() }` and `.task { seedUITestDataIfNeeded() }` are only on the WindowGroup — also correct
- The Settings window shares the same `ModelContainer` instance, so SwiftData changes in one window are visible in the other

### Potential Issues
- **Window restoration**: `Settings` scenes are non-restorable by default on macOS, which is standard behavior. No issue expected.
- **Multiple windows**: `Settings` scenes are single-instance. SwiftUI handles this — pressing Cmd+Comma when settings is already open brings it to front rather than creating a new window.
- **NavigationStack depth in Settings**: If a user navigates deep (Settings > Project > Milestone) and closes the window, the navigation state is lost. This is acceptable for a settings window.
- **UI tests**: Existing UI tests for settings (`testSettingsHasBackChevron`, `testTappingGearPushesSettingsView`) are iOS-only (run on iPhone simulator). If UI tests are ever run on macOS, they would need platform-specific expectations since `SettingsLink` opens a separate window rather than pushing.

## Completeness Assessment

### Fully Implemented
- Settings scene with NavigationStack and exhaustive destination handling
- SettingsLink on macOS dashboard toolbar
- Environment and model container injection for the Settings scene
- Removal of unnecessary back button and toolbar on macOS settings
- iOS behavior unchanged
- CHANGELOG updated
- Spec documents (smolspec, tasks, decision log) created

### Not Applicable / Out of Scope
- No window size customization (`.defaultSize()`) — tested acceptable with defaults
- No ViewModifier extraction for environment duplication — only two call sites
- No changes to NavigationDestination enum

### No Gaps Identified
All eight smolspec requirements are satisfied by the implementation.
