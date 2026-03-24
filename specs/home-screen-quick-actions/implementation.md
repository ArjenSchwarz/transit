# Home Screen Quick Actions — Implementation Explanation

## Beginner Level

### What Changed
Transit now supports iOS "Home Screen Quick Actions" — the menu that appears when you long-press (force-touch) the app icon. A "New Task" shortcut appears with a `+` icon. Tapping it opens the app directly into the "Add Task" form, skipping the usual navigation.

### Why It Matters
Users who frequently create tasks can now do so with fewer taps. Instead of opening Transit, waiting for the dashboard, and hitting the `+` button, they long-press the icon and tap "New Task." It's a small convenience that adds up over time.

### Key Concepts
- **Quick Actions / Shortcut Items**: iOS lets apps register menu items on their app icon. These can be "static" (defined in a config file, always available) or "dynamic" (set in code, changing based on app state). Transit uses a static one.
- **Info.plist**: A configuration file every iOS app has. By adding a `UIApplicationShortcutItems` entry here, iOS knows to show the "New Task" action without any code running first.
- **Cold start vs warm start**: "Cold" means the app isn't running at all — iOS launches it fresh. "Warm" means the app is in the background. The quick action must work in both cases, and the implementation handles each differently.
- **`#if os(iOS)`**: Since Transit also runs on macOS (which doesn't have Home Screen Quick Actions), all the new code is wrapped in platform checks so it only compiles on iOS.

---

## Intermediate Level

### Changes Overview
4 commits, 8 files changed (251 lines added). The implementation touches:

| File | Purpose |
|------|---------|
| `Info.plist` | Static `UIApplicationShortcutItems` entry with type, title, and SF Symbol |
| `QuickActionService.swift` | New `@Observable` class with a `pendingNewTask` boolean flag |
| `TransitApp.swift` | `QuickActionAppDelegate` (cold start), `QuickActionSceneDelegate` (warm start), service wiring |
| `DashboardView.swift` | `.onChange(of:)` observer that presents `AddTaskSheet` when the flag fires |
| `QuickActionServiceTests.swift` | Basic unit tests for the service's flag behavior |
| `smolspec.md` / `tasks.md` | Specification and task tracking |
| `CHANGELOG.md` | Release notes |

### Implementation Approach
The architecture bridges UIKit's delegate-based quick action API with SwiftUI's declarative observation model using three components:

1. **`QuickActionService`** — A minimal `@Observable` class holding a `pendingNewTask` boolean and a shared `newTaskActionType` string constant. Acts as a message bus between UIKit delegates and SwiftUI views.

2. **`QuickActionAppDelegate`** — Registered via `@UIApplicationDelegateAdaptor`. Handles the cold-start path: when iOS creates a new scene session, `configurationForConnecting:options:` checks if the connection was triggered by a shortcut item and sets the flag. It also configures `QuickActionSceneDelegate` as the scene delegate class.

3. **`QuickActionSceneDelegate`** — Handles the warm-start path via `windowScene(_:performActionFor:completionHandler:)`. In scene-based apps (all SwiftUI apps), this is where iOS delivers quick actions when the app is already running. It reaches the service through `UIApplication.shared.delegate`.

4. **DashboardView** consumes the flag via `@Environment(QuickActionService.self)` and an `.onChange(of:)` modifier. When `pendingNewTask` becomes `true`, it clears the flag, checks `DashboardLogic.shouldHandleNewTaskShortcut` (preventing double-presentation if a sheet is already open), and sets `showAddTask = true`.

### Trade-offs
- **Static vs dynamic shortcut**: Static was chosen because the only action ("New Task") never changes. No code runs to register it — it's always available from first install.
- **Scene delegate vs app delegate for warm start**: The spec originally suggested `application(_:performActionFor:)` on the app delegate, but in scene-based apps this callback isn't called. The implementation correctly uses `UIWindowSceneDelegate` instead.
- **Boolean flag vs enum/queue**: A simple `Bool` works for a single action type. If multiple quick actions were added, this would need to become an optional enum or a queue. Acceptable for V1 scope.

---

## Expert Level

### Technical Deep Dive
The implementation navigates a known tension point in SwiftUI: the framework has no native API for handling `UIApplicationShortcutItem`. Unlike `NSUserActivity` (which has `onContinueUserActivity`), shortcut items require UIKit delegate callbacks, making `@UIApplicationDelegateAdaptor` the only viable approach.

**Timing considerations**: On cold start, `configurationForConnecting:options:` fires before the SwiftUI view hierarchy exists. The `@Observable` flag is set, but `DashboardView`'s `.onChange(of:)` won't fire until the view is in the hierarchy. This works because SwiftUI's observation system picks up the already-`true` state when the view first evaluates, triggering the `onChange` closure. The `guard isPending else { return }` filters out the subsequent `false` transition when the flag is cleared.

**Scene delegate coupling**: `QuickActionSceneDelegate` accesses the service via `UIApplication.shared.delegate as? QuickActionAppDelegate` — an unavoidable coupling because UIKit instantiates scene delegates by class (via `config.delegateClass`), not by instance. There's no way to inject dependencies into the scene delegate at creation time.

**MainActor isolation**: `QuickActionService` is implicitly `@MainActor` due to the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting. The delegates are also `@MainActor` (UIKit callbacks are main-thread). The entire flow stays on the main actor with no concurrency boundary crossings.

### Architecture Impact
- **Minimal surface area**: The feature adds one new service, two delegate classes, and a single `.onChange` modifier. No existing APIs were modified.
- **Follows existing patterns**: Service creation in `TransitApp.init()`, environment injection via `.environment()`, and the `shouldHandleNewTaskShortcut` guard are all pre-existing patterns reused here.
- **macOS isolation**: All new code is behind `#if os(iOS)`. The `UIApplicationShortcutItems` plist key is iOS-only and silently ignored on macOS.

### Potential Issues
- **Silent failure on delegate cast**: If `UIApplication.shared.delegate` is not a `QuickActionAppDelegate` (shouldn't happen, but defensive), the `as?` cast fails silently and the warm-start quick action is swallowed. No crash, but no action either.
- **Sheet conflicts with deep navigation**: If the user has navigated deep into a pushed view (e.g., settings), the quick action presents the AddTaskSheet over that view. The spec explicitly marks this as acceptable for V1.
- **No queuing**: If a quick action arrives while the flag is being consumed (theoretically impossible since everything is `@MainActor`), it could be lost. The single-threaded guarantee makes this a non-issue in practice.

---

## Completeness Assessment

### Fully Implemented
- Static shortcut item in Info.plist with correct type, title, and SF Symbol
- Cold-start handling via `configurationForConnecting:options:`
- Warm-start handling via `QuickActionSceneDelegate`
- `QuickActionService` as observable bridge between UIKit and SwiftUI
- DashboardView observation with `shouldHandleNewTaskShortcut` guard
- All code gated behind `#if os(iOS)`
- Unit tests for QuickActionService
- CHANGELOG updated

### Not Applicable / Out of Scope
- Dynamic quick actions (future feature)
- macOS Dock menu equivalents (future feature)
- NavigationStack pop-to-root before presenting sheet (V1 decision: present over current view)
- Additional quick action types beyond "New Task"
