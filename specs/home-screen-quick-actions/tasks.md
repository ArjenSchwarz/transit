---
references:
    - specs/home-screen-quick-actions/smolspec.md
---
# Home Screen Quick Actions

## Core Implementation

- [ ] 1. Static quick action defined in Info.plist <!-- id:6yfh7qs -->
  - Add UIApplicationShortcutItems to Transit/Transit/Info.plist with a single New Task action (type: com.arjen.transit.new-task, SF Symbol: plus.square).
  - Verify by building for iOS and long-pressing the app icon in Simulator — the New Task action appears.
  - References: specs/home-screen-quick-actions/smolspec.md

- [ ] 2. QuickActionService communicates pending actions to views <!-- id:6yfh7qt -->
  - Create an @Observable QuickActionService class (iOS only) with a pendingNewTask flag.
  - Initialize it in TransitApp.init() and inject via .environment().
  - Verify: service compiles, is accessible via @Environment in a view, and the flag can be toggled.
  - Blocked-by: 6yfh7qs (Static quick action defined in Info.plist)
  - References: specs/home-screen-quick-actions/smolspec.md

- [ ] 3. AppDelegate handles quick actions on warm and cold start <!-- id:6yfh7qu -->
  - Create an AppDelegate class (iOS only, via @UIApplicationDelegateAdaptor) that sets QuickActionService.pendingNewTask on both warm start (performActionFor:) and cold start (configurationForConnecting:options:).
  - Verify: trigger quick action in Simulator for both scenarios — flag is set.
  - Blocked-by: 6yfh7qt (QuickActionService communicates pending actions to views)
  - References: specs/home-screen-quick-actions/smolspec.md

- [ ] 4. DashboardView presents AddTaskSheet on quick action <!-- id:6yfh7qv -->
  - DashboardView observes QuickActionService via @Environment.
  - When pendingNewTask becomes true and shouldHandleNewTaskShortcut allows it, set showAddTask = true and clear the flag.
  - Verify: long-press app icon → tap New Task → AddTaskSheet appears.
  - Blocked-by: 6yfh7qu (AppDelegate handles quick actions on warm and cold start)
  - References: specs/home-screen-quick-actions/smolspec.md

## Edge Cases and Testing

- [ ] 5. Quick action is ignored when a sheet is already presented <!-- id:6yfh7qw -->
  - Verify that tapping the quick action while AddTaskSheet or TaskDetailView sheet is already showing does not cause a crash or double-presentation.
  - The existing shouldHandleNewTaskShortcut guard handles this.
  - Verify: open a task detail sheet, background the app, trigger quick action, foreground — no crash, existing sheet remains.
  - Blocked-by: 6yfh7qv (DashboardView presents AddTaskSheet on quick action)
  - References: specs/home-screen-quick-actions/smolspec.md

- [ ] 6. Unit tests for QuickActionService <!-- id:6yfh7qx -->
  - Add tests verifying: flag defaults to false, setting flag to true works, clearing the flag after consumption works.
  - Use Swift Testing framework with @Suite(.serialized).
  - Blocked-by: 6yfh7qt (QuickActionService communicates pending actions to views)
  - References: specs/home-screen-quick-actions/smolspec.md

- [ ] 7. macOS build unaffected <!-- id:6yfh7qy -->
  - Verify make build-macos succeeds with no warnings related to quick action code.
  - All new code must be gated behind #if os(iOS).
  - Blocked-by: 6yfh7qv (DashboardView presents AddTaskSheet on quick action)
  - References: specs/home-screen-quick-actions/smolspec.md
