# Bugfix Report: Sync Toggle Does Not Update SyncManager Runtime State

**Date:** 2026-04-03
**Status:** Fixed

## Description of the Issue

The iCloud Sync toggle in Settings updates the `@AppStorage("syncEnabled")` UserDefaults value but never calls `SyncManager.setSyncEnabled(_:)`. This means `SyncManager.isSyncEnabled` -- which is read once during `init()` -- remains stale for the duration of the session. Any runtime behavior guarded by `isSyncEnabled` (notably the heartbeat in `startHeartbeat(context:)`) uses the stale value.

**Reproduction steps:**
1. Launch with sync enabled.
2. Disable iCloud Sync in Settings.
3. Toggle the MCP server off/on (or any flow that calls `startHeartbeat`).
4. Observe: heartbeat still starts because `SyncManager.isSyncEnabled` remains `true`.

**Impact:** The sync toggle appears functional but has no runtime effect until the app is restarted. This also affects the inverse case (enabling sync after launching with it disabled).

## Investigation Summary

- **Symptoms examined:** `SyncManager.isSyncEnabled` stays at its init-time value regardless of toggle changes during the session.
- **Code inspected:** `SyncManager.swift` (init, `setSyncEnabled`, `startHeartbeat`), `SettingsView.swift` (iOS and macOS sync toggles), `TransitApp.swift` (environment injection).
- **Hypotheses tested:** The `SyncManager` already has a correct `setSyncEnabled(_:)` method that updates both the runtime property and UserDefaults. The issue is simply that the settings toggle bypasses it.

## Discovered Root Cause

`SettingsView` binds the sync toggle directly to `@AppStorage("syncEnabled")`, which writes to UserDefaults but does not update `SyncManager.isSyncEnabled`. The `SyncManager.setSyncEnabled(_:)` API exists and correctly updates both the runtime property and UserDefaults, but it was never called by the UI.

**Defect type:** Missing integration -- UI bypass of service layer API.

**Why it occurred:** The `@AppStorage` binding was a convenient shorthand for persisting the preference, but it skipped the service layer. The `SyncManager` was only available in the macOS `#if os(macOS)` block of `SettingsView`, so the iOS toggle had no access to it at all.

**Contributing factors:** The `SyncManager` was already injected into the environment for both platforms (in `TransitApp.swift`), but `SettingsView` only declared the `@Environment(SyncManager.self)` property inside the macOS-specific block.

## Resolution for the Issue

**Changes made:**
- `SettingsView.swift` - Moved `@Environment(SyncManager.self)` from the macOS-only block to the shared (cross-platform) property declarations.
- `SettingsView.swift` (iOS) - Added `.onChange(of: syncEnabled)` handler on the iOS sync toggle that calls `syncManager.setSyncEnabled(enabled)`.
- `SettingsView.swift` (macOS) - Added `.onChange(of: syncEnabled)` handler on the macOS sync toggle that calls `syncManager.setSyncEnabled(enabled)`.

**Approach rationale:** The `@AppStorage` binding is kept for the toggle's two-way UI binding and persistence. The `.onChange` handler mirrors the value into `SyncManager` so runtime state stays consistent. This is the minimal change that fixes the bug without restructuring how the toggle works.

**Alternatives considered:**
- Replace `@AppStorage` with a custom binding through `SyncManager` -- rejected because it would require making `SyncManager` `@Bindable` or adding a computed binding property, which is more invasive for no additional benefit.
- Observe UserDefaults changes inside `SyncManager` -- rejected because it adds implicit coupling; explicit `.onChange` is clearer and more discoverable.

## Regression Test

**Test file:** `Transit/TransitTests/SyncManagerTests.swift`
**Test name:** `setSyncEnabled_updatesRuntimeState`, `init_readsCurrentUserDefaultsValue`, `setSyncEnabled_persistsToUserDefaults`

**What it verifies:** That `setSyncEnabled(_:)` correctly updates the runtime `isSyncEnabled` property and persists to UserDefaults, and that `init()` reads the current UserDefaults value.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Settings/SettingsView.swift` | Move `@Environment(SyncManager.self)` to shared scope; add `.onChange` handlers on both iOS and macOS sync toggles |
| `Transit/TransitTests/SyncManagerTests.swift` | New regression tests for SyncManager state consistency |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

**Manual verification:**
- Build succeeds for both iOS and macOS targets

## Prevention

**Recommendations to avoid similar bugs:**
- When a service has a setter API (like `setSyncEnabled`), UI should always route through it rather than writing directly to the backing store.
- Consider adding a note in `SyncManager` that `setSyncEnabled` is the canonical way to change sync state, and that `@AppStorage` alone is insufficient.

## Related

- T-699: Sync toggle does not update SyncManager runtime state
