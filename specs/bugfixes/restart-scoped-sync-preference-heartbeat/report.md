# Bugfix Report: Restart-Scoped Sync Preference Changes Heartbeat

**Date:** 2026-08-05
**Status:** Fixed

## Description of the Issue

The iCloud Sync preference is explicitly restart-scoped: a live SwiftData container continues in the CloudKit mode selected at launch. Despite that contract, `SyncManager.setSyncEnabled(false)` stopped the live heartbeat immediately, and `startHeartbeat` used the mutable preference rather than the launch-fixed mode.

**Reproduction steps:**
1. Launch Transit with iCloud Sync active and MCP enabled, so the heartbeat is running.
2. Turn iCloud Sync off in Settings, then turn it back on without relaunching.
3. Observe that Settings reports no pending restart change, but the heartbeat remains stopped until MCP is toggled or Transit restarts.

**Impact:** The MCP workflow could stop proactively pulling remote CloudKit changes for the rest of the launch, while the UI said its effective sync mode was unchanged.

## Investigation Summary

- **Symptoms examined:** Preference-off immediately cancelled the heartbeat; restoring the preference did not recreate it.
- **Code inspected:** `SyncManager.setSyncEnabled`, `SyncManager.startHeartbeat`, `SettingsView` sync/MCP controls, and `TransitApp.startMCPServerIfEnabled`.
- **Hypotheses tested:** The live CloudKit container mode is fixed at launch and already represented by `isCloudSyncActive`; only heartbeat lifecycle incorrectly read `isSyncEnabled`.

## Discovered Root Cause

`SyncManager` conflated its mutable persisted preference with the fixed CloudKit mode of the current launch at the heartbeat lifecycle boundary.

**Defect type:** Logic error / stale state authority.

**Why it occurred:** T-699 implemented immediate runtime preference propagation and stopped the timer on disable. T-1797/T-1857 later established that direct CloudKit work must follow `isCloudSyncActive` because the container cannot be live-reconfigured, but this timer lifecycle retained the former preference-based behavior.

**Contributing factors:** Existing tests asserted immediate-stop semantics without starting a real heartbeat, so they did not model the launch-mode contract or the off/on reversion sequence.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/SyncManager.swift` — `setSyncEnabled` now persists only the restart-scoped preference; it does not alter the live heartbeat.
- `Transit/Transit/Services/SyncManager.swift` — `startHeartbeat` replaces any existing task and gates new scheduling on the launch-fixed `isCloudSyncActive` mode.
- `Transit/TransitTests/SyncManagerTests.swift` — replaced obsolete immediate-stop expectations with active-launch, inactive-fallback, preference-reversion, and explicit-stop regressions.

**Approach rationale:** The live container cannot change CloudKit configuration until relaunch, so heartbeat eligibility must share its single fixed authority. `stopHeartbeat()` remains the explicit lifecycle control used by the MCP toggle; `TransitApp.startMCPServerIfEnabled` remains unchanged, preserving T-1767’s start-after-MCP-attempt behavior.

**Alternatives considered:**
- Restart the heartbeat when the preference is restored — rejected because it leaves the active launch incorrectly stopped after the off toggle.
- Rebuild the live SwiftData container on preference changes — rejected by Decision 21 and outside T-1937’s scope.

## Regression Test

**Test file:** `Transit/TransitTests/SyncManagerTests.swift`
**Test names:** `settingSyncOffKeepsHeartbeatRunningForCloudActiveLaunch`, `settingSyncOnDoesNotStartHeartbeatForCloudInactiveLaunch`, `revertingSyncPreferenceLeavesActiveLaunchHeartbeatRunning`, `explicitHeartbeatStopStillControlsActiveLaunchLifecycle`

**What it verifies:** An active launch keeps its timer through preference-off and reversion; an inactive fallback launch cannot begin a timer from a preference-on; explicit lifecycle shutdown still stops the timer.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/SyncManager.swift` | Base heartbeat eligibility on launch-fixed CloudKit mode; remove preference-driven stop |
| `Transit/TransitTests/SyncManagerTests.swift` | Add active/fallback/reversion/MCP lifecycle regressions |
| `specs/bugfixes/restart-scoped-sync-preference-heartbeat/report.md` | Investigation and resolution record |
| `CHANGELOG.md` | User-visible fix entry |

## Verification

**Automated:**
- [x] Regression tests fail before the fix (pre-fix `make test-quick` exited 2)
- [x] Regression tests pass after the fix (`make test-quick`; focused iOS `TransitTests/SyncManagerTests`)
- [ ] Full test suite passes — `make test` exceeded the 120-second command limit after reaching test execution and surfaced unrelated existing UI failures in `testClearAll`, `testEditViewPreservesTaskMilestone`, and `testDataMaintenanceGoldenPath`
- [x] Linters/validators pass (`make lint`)

**Manual verification:**
- Inspect the macOS Settings wiring: only the MCP enable toggle invokes `startHeartbeat`/`stopHeartbeat`; iCloud Sync only calls `setSyncEnabled`, which now preserves live launch behavior.

## Prevention

- Treat `isCloudSyncActive` as the sole authority for operations whose availability is fixed by the live container.
- Keep explicit MCP lifecycle operations as the only runtime start/stop control for the heartbeat.

## Related

- T-1937
- T-1797 / T-1857 — active CloudKit mode and restart-scoped preference contract
- T-1767 — heartbeat lifecycle after MCP startup failure (preserved)
