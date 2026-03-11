# macOS Settings Window

## Overview

On macOS, the Settings view is currently pushed onto the main `NavigationStack` like any other destination. Standard macOS apps present settings in a dedicated, movable preferences window (opened via Cmd+Comma or the app menu). This change makes Transit follow that convention by using SwiftUI's built-in `Settings` scene on macOS, while keeping the existing push-based navigation on iOS unchanged.

## Requirements

- The system MUST present settings in a separate macOS window using SwiftUI's `Settings` scene on macOS.
- The system MUST support opening settings via the standard Cmd+Comma keyboard shortcut (provided automatically by the `Settings` scene).
- The system MUST replace the settings toolbar button in `DashboardView` with a `SettingsLink` on macOS so it opens the settings window instead of pushing onto the NavigationStack.
- The system MUST provide sub-navigation within the settings window for ProjectEdit, MilestoneEdit, Acknowledgments, and LicenseText views via a local `NavigationStack` with `navigationDestination(for:)`.
- The system MUST handle all `NavigationDestination` cases in the settings scene's `navigationDestination` handler (the switch must be exhaustive; unreachable cases like `.settings` and `.report` can render `EmptyView()`).
- The system MUST pass all required environment objects (`TaskService`, `ProjectService`, `CommentService`, `MilestoneService`, `SyncManager`, `ConnectivityMonitor`, `MCPSettings`, `MCPServer`, `resolvedTheme`) and the `modelContainer` to the `Settings` scene.
- The system MUST keep iOS settings navigation unchanged (push onto root `NavigationStack`).
- The system SHOULD remove the custom back/dismiss toolbar button and `.navigationBarBackButtonHidden(true)` from `SettingsView` on macOS, since the settings window is the root view (no back destination) and sub-views will show the system back button automatically when pushed.

## Implementation Approach

**Files to modify:**

1. **`Transit/Transit/TransitApp.swift`** (lines 101-149) — Add a `Settings` scene inside `#if os(macOS)` after the `WindowGroup`. The scene wraps `SettingsView()` in a `NavigationStack` with `navigationDestination(for: NavigationDestination.self)` handling all cases exhaustively. Attach all `.environment()` modifiers, `.preferredColorScheme()`, and `.modelContainer(container)`. Reference pattern: the existing `WindowGroup` environment setup at lines 122-140. Consider extracting the shared environment modifiers into a `ViewModifier` to avoid duplication between WindowGroup and Settings scenes.

2. **`Transit/Transit/Views/Dashboard/DashboardView.swift`** (lines 111-116) — Replace the `NavigationLink(value: NavigationDestination.settings)` with `SettingsLink` inside `#if os(macOS)`, keeping the `NavigationLink` for `#else` (iOS). `SettingsLink` accepts a custom `label:` parameter, so use `Label("Settings", systemImage: "gear")` to match the current appearance.

3. **`Transit/Transit/Views/Settings/SettingsView.swift`** — Two changes on macOS:
   - Remove `.toolbar { settingsToolbar }` from the `macOSSettings` computed property (line 121). The settings window has standard window close controls and no need for a custom back button.
   - Remove `.navigationBarBackButtonHidden(true)` from `macOSSettings` (line 119). This allows the system back button to appear when sub-views (ProjectEditView, AcknowledgmentsView, etc.) are pushed onto the settings window's NavigationStack.

**Existing patterns leveraged:**
- `#if os(macOS)` / `#else` platform branching (SettingsView, DashboardView, TransitApp)
- Environment injection pattern from TransitApp.swift lines 131-140
- `navigationDestination(for: NavigationDestination.self)` routing at TransitApp.swift lines 105-119

**Dependencies:**
- SwiftUI `Settings` scene and `SettingsLink` view
- Existing `NavigationDestination` enum (no changes needed)
- All existing environment objects and services

**Out of Scope:**
- No changes to `NavigationDestination` enum
- No changes to SettingsView layout or content
- No changes to iOS navigation behavior
- No changes to ProjectEditView, MilestoneEditView, AcknowledgmentsView, or LicenseTextView
- No tab-based settings layout (single scrolling view is fine for now)
- No window size customization (test the default; add `.defaultSize()` only if needed)

## Risks and Assumptions

- **Risk:** `NavigationStack` push navigation inside a `Settings` scene may behave unexpectedly (e.g., window not resizing for pushed sub-views, clipped content). | **Mitigation:** Test at runtime. If push navigation doesn't work well, fall back to using a `Window(id: "settings")` scene instead, opened via `@Environment(\.openWindow)`. This requires more code but gives full control over window behavior.
- **Risk:** Environment objects may not propagate correctly to the `Settings` scene since it's a separate window. | **Mitigation:** Explicitly attach all `.environment()` modifiers and `.modelContainer()` to the `Settings` scene, mirroring the `WindowGroup` setup. Verify at runtime that services and `@Query` results are accessible.
- **Risk:** `SettingsLink` may not render correctly in a Liquid Glass toolbar. | **Mitigation:** Verify visually. If styling is wrong, fall back to `Button` with `NSApp.sendAction(#selector(NSApplication.showSettingsWindow), to: nil, from: nil)`.
- **Assumption:** The `Settings` scene automatically registers the Cmd+Comma shortcut and the "Settings..." menu item in the app menu. This is standard SwiftUI behavior on macOS.
- **Assumption:** `@AppStorage` values changed in the settings window propagate to the main window immediately, since `@AppStorage` is backed by `UserDefaults` which is shared across scenes. Verify that theme changes in settings update the dashboard in real time.
- **Prerequisite:** The `.settings` case in `NavigationDestination` remains necessary for iOS. On macOS it becomes unreachable in the root `WindowGroup`'s destination handler but causes no harm.
