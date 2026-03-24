# Home Screen Quick Actions

## Overview

Transit has no Home Screen Quick Actions. Users must open the app and tap the "+" button to create a task. This change adds a static quick action to the iOS app icon so long-pressing it shows a "New Task" shortcut that launches the app directly into the Add Task sheet. This is iOS-only — macOS has no equivalent feature.

## Requirements

- The system MUST show a "New Task" quick action when the user long-presses the Transit app icon on iOS
- The system MUST present the Add Task sheet when the user taps the "New Task" quick action
- The system MUST handle the quick action on both cold launch (app not running) and warm resume (app in background)
- The system MUST use a static shortcut item defined in Info.plist (no dynamic registration needed)
- The system MUST NOT present the Add Task sheet if it (or the task detail sheet) is already showing — reuse the existing `DashboardLogic.shouldHandleNewTaskShortcut` guard
- The quick action SHOULD use the SF Symbol `plus.square` as its icon
- The system MUST NOT affect macOS — all quick action code MUST be gated behind `#if os(iOS)`

## Implementation Approach

**Static shortcut definition** in `Transit/Transit/Info.plist`: add a `UIApplicationShortcutItems` array with a single item of type `com.arjen.transit.new-task`, title "New Task", and SF symbol icon. Note: `UIApplicationShortcutItems` is an iOS-only key; macOS ignores it, so no `#if` guard is needed in the plist.

**Quick action handling** via `@UIApplicationDelegateAdaptor` in `Transit/Transit/TransitApp.swift`. A small `AppDelegate` class (iOS only, gated with `#if os(iOS)`) handles two cases:
- **Warm start**: `application(_:performActionFor:completionHandler:)` is called when the app is already running. Set a flag on a shared `@Observable` handler.
- **Cold start**: `application(_:configurationForConnecting:options:)` receives the shortcut item in `UIScene.ConnectionOptions.shortcutItem`. Set the same flag.

Note: `onContinueUserActivity` is NOT suitable here — Home Screen Quick Actions use `UIApplicationShortcutItem`, not `NSUserActivity`. The `@UIApplicationDelegateAdaptor` approach is the documented method for SwiftUI apps.

**State communication** via a shared `@Observable` class (`QuickActionService` or similar):
1. Created in `TransitApp.init()`, injected into the view hierarchy via `.environment()`
2. `AppDelegate` stores a reference and sets `pendingNewTask = true` when a quick action fires
3. `DashboardView` observes this via `@Environment(QuickActionService.self)` and, when the flag becomes true, sets `showAddTask = true` then clears the flag
4. The guard logic from `DashboardLogic.shouldHandleNewTaskShortcut` prevents double-presentation

**Key files to modify:**
- `Transit/Transit/Info.plist` — add `UIApplicationShortcutItems` array
- `Transit/Transit/TransitApp.swift` — add `QuickActionService`, `AppDelegate` (iOS only), `@UIApplicationDelegateAdaptor`, inject service into environment

**Key files to modify (minor):**
- `Transit/Transit/Views/Dashboard/DashboardView.swift` — observe `QuickActionService` and trigger `showAddTask` when pending action arrives

**Existing patterns to follow:**
- `DashboardLogic.shouldHandleNewTaskShortcut` (DashboardView.swift:141-142) — same guard used by "t" key shortcut to prevent double-presentation
- `#if os(macOS)` / `#if os(iOS)` guards used throughout TransitApp.swift and DashboardView.swift
- Environment injection pattern: services created in `TransitApp.init()`, injected via `.environment()` (TransitApp.swift:135-139)
- `showAddTask` state in DashboardView.swift:13 — the single control point for AddTaskSheet presentation

**Dependencies:**
- `DashboardView.showAddTask` (`@State`, DashboardView.swift:13) — controls sheet presentation
- `DashboardLogic.shouldHandleNewTaskShortcut` — existing guard for preventing sheet conflicts
- `AddTaskSheet` view — presented by the existing `.sheet(isPresented: $showAddTask)` modifier
- UIKit `UIApplicationShortcutItem` API — iOS only

**Out of Scope:**
- Dynamic quick actions (e.g., "Recent Project" shortcuts)
- macOS equivalents (Dock menu items)
- Deep linking to specific projects or task types via quick actions
- Additional quick actions beyond "New Task"
- Popping the NavigationStack if a child view is pushed (the sheet presents over whatever is visible — acceptable for V1)

## Risks and Assumptions

- **Risk:** `@UIApplicationDelegateAdaptor` may interfere with the existing TransitApp init (service setup, model container) | **Mitigation:** The AppDelegate only handles shortcut items — it doesn't participate in data layer initialization. TransitApp.init() runs independently.
- **Risk:** Cold-start quick action may arrive before DashboardView is fully rendered | **Mitigation:** SwiftUI's `.sheet(isPresented:)` naturally defers presentation until the view hierarchy is ready. Using `.onChange(of:)` on the observable flag ensures the sheet is triggered after the view is in the hierarchy.
- **Risk:** If a sheet (task detail or add task) is already presented, the quick action could conflict | **Mitigation:** Reuse `DashboardLogic.shouldHandleNewTaskShortcut` guard; if it returns false, ignore the pending action.
- **Assumption:** Static `UIApplicationShortcutItems` in Info.plist work with the SwiftUI App lifecycle without additional configuration.
- **Assumption:** `@UIApplicationDelegateAdaptor` is compatible with the existing TransitApp init pattern (custom `ModelContainer` setup, service injection).
