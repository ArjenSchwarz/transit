# Bugfix Report: iOS Quick Action Can Be Consumed by Wrong Window

**Date:** 2026-03-27
**Status:** Fixed
**Ticket:** T-593

## Description of the Issue

On iPadOS with multiple windows open, triggering the "New Task" home screen quick action could open the Add Task sheet in a different window than the one that received the shortcut, or the action could appear to be silently dropped.

**Reproduction steps:**
1. Open Transit on iPad and create a second window (Split View or Stage Manager)
2. Both windows show the kanban dashboard
3. Long-press the Transit app icon and select "New Task" quick action
4. Observe: the Add Task sheet may appear in either window, not necessarily the foreground one

**Impact:** Poor user experience in iPadOS multi-window. The quick action becomes unreliable when multiple scenes exist, as any scene can race to consume the shared flag.

## Investigation Summary

- **Symptoms examined:** Add Task sheet opening in wrong window or not appearing at all
- **Code inspected:** `QuickActionService.swift` (global boolean), `TransitApp.swift` (scene/app delegates), `DashboardView.swift` (`.onChange` handler consuming the flag)
- **Root cause identified via:** Code tracing the quick action delivery path from UIKit delegates through QuickActionService to DashboardView

## Discovered Root Cause

`QuickActionService` used a single shared boolean (`pendingNewTask`) for all scenes. When a quick action was triggered:

1. The app/scene delegate set `pendingNewTask = true` on the shared service
2. Every `DashboardView` instance observed this change via `.onChange(of: quickActionService.pendingNewTask, initial: true)`
3. The first `DashboardView` to process the change would clear the flag (`pendingNewTask = false`) and present the sheet
4. In multi-window, this was non-deterministic — any scene could win the race

**Defect type:** Shared mutable state across scenes — missing per-scene scoping.

**Why it occurred:** The original implementation assumed a single-window environment. The quick action feature was built for iPhone where only one scene exists at a time.

**Contributing factors:** SwiftUI's `@Observable` + `.onChange` propagation order across multiple scenes is not guaranteed, making the race condition unpredictable.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/QuickActionService.swift` — Replaced `pendingNewTask: Bool` with `pendingSceneSessionIDs: [String]` and methods `requestNewTask(forSceneSession:)`, `consumeNewTask(forSceneSession:)`, `hasPendingAction(forSceneSession:)`
- `Transit/Transit/TransitApp.swift` — Updated `QuickActionAppDelegate` to pass `connectingSceneSession.persistentIdentifier` and `QuickActionSceneDelegate` to pass `windowScene.session.persistentIdentifier`
- `Transit/Transit/Extensions/SceneSessionReader.swift` — New file: UIViewRepresentable bridge that discovers the hosting `UIWindowScene` session identifier and exposes it via `@Environment(\.sceneSessionID)`
- `Transit/Transit/Views/Dashboard/DashboardView.swift` — Reads `sceneSessionID` from environment, observes `pendingSceneSessionIDs`, and only consumes actions matching its own scene

**Approach rationale:** Per-scene state via scene session identifiers is the natural fit because UIKit already provides the scene identity at both cold-start (app delegate) and warm-start (scene delegate) paths. The UIViewRepresentable bridge is a lightweight, standard pattern for exposing UIKit scene identity to SwiftUI views.

**Alternatives considered:**
- Routing to `UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive })` — fragile in multi-window where multiple scenes can be foreground
- Using `@FocusedValue` to route the action — would require the target window to have focus, which is not guaranteed during cold start

## Regression Test

**Test file:** `Transit/TransitTests/QuickActionServiceTests.swift`
**Test names:** `pendingScopedToScene`, `consumeClearsMatchingScene`, `consumeReturnsFalseForWrongScene`, `multipleScenesPending`, `pendingSceneSessionIDsObservable`

**What it verifies:** That pending actions are scoped to specific scene session IDs, that only the matching scene can consume its action, and that independent scenes maintain separate pending state.

**Run command:** `make test` (iOS Simulator — tests are `#if os(iOS)`)

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/QuickActionService.swift` | Replaced global boolean with per-scene tracking |
| `Transit/Transit/TransitApp.swift` | Pass scene session identifiers to QuickActionService |
| `Transit/Transit/Extensions/SceneSessionReader.swift` | New: UIKit-to-SwiftUI scene session bridge |
| `Transit/Transit/Views/Dashboard/DashboardView.swift` | Consume action only for own scene |
| `Transit/TransitTests/QuickActionServiceTests.swift` | Updated tests for per-scene API |

## Verification

**Automated:**
- [x] Regression tests written (per-scene scoping, consumption, independence)
- [x] Linter passes (0 violations)
- [ ] Full test suite passes (pre-existing build error on main blocks test runner)

**Manual verification:**
- Build compiles for iOS with no new errors (pre-existing concurrency error on line 85 is unrelated)

## Prevention

**Recommendations to avoid similar bugs:**
- When adding state to services shared across scenes, always consider iPadOS multi-window — prefer per-scene state over global booleans
- Document which services are scene-scoped vs app-scoped in agent notes

## Related

- T-27: Home Screen Quick Actions for iOS (original feature)
- `specs/home-screen-quick-actions/` — original feature spec
