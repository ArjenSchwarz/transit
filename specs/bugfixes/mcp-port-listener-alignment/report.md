# Bugfix Report: MCP Port Listener Alignment

**Date:** 2026-08-05
**Status:** Fixed

## Description of the Issue

The macOS MCP Settings port field persisted a numeric value when the field committed, including when it lost focus or Settings closed. The running MCP listener restarted only from the TextField's `onSubmit` handler. Consequently, a focus-loss commit persisted and advertised a new port while the embedded MCP server remained bound to its previous port.

**Reproduction steps:**
1. Enable the MCP server and wait for it to listen on its configured port.
2. Enter a different valid port in Settings.
3. Click elsewhere or close Settings without pressing Return.
4. Observe that the setup command uses the persisted new port while the live listener remains on the old port.

**Impact:** Agents following the displayed setup command could not connect until a later restart or app relaunch. The persisted configuration and active runtime state were misleadingly divergent.

## Investigation Summary

### Phase 1 — Initial overview

Expected behavior is that every committed enabled-server port value converges through the existing serialized MCP lifecycle coordinator, regardless of whether commit came from Return or focus loss. The setup command must describe the active listener, not an un-applied draft.

Actual behavior was limited to `TextField.onSubmit`, so focus-loss commits received no lifecycle request. No runtime error was emitted because the old listener remained healthy.

### Phase 2 — Systematic inspection

- `Transit/Transit/Views/Settings/SettingsView.swift` bound the port directly to `MCPSettings.port` and called `scheduleMCP(.restart)` only from `onSubmit`.
- `Transit/Transit/MCP/MCPSettings.swift` persists every binding update through `didSet`, independently of listener state.
- `Transit/Transit/MCP/MCPServer.swift` already had a desired-state coordinator: `start(port:)` validates ports, coalesces duplicate desired states, tears down old listeners before binding a replacement, and stops for invalid ports.
- `SettingsView` rendered the setup command directly from the persisted `mcpSettings.port`, which could differ from the active listener during an un-applied or in-flight change.

### Phase 3 — Root cause analysis

1. Why did focus loss leave the old listener bound? The lifecycle request existed only in `onSubmit`.
2. Why did the displayed command change anyway? The `TextField` binding committed directly to UserDefaults-backed `MCPSettings.port`.
3. Why was there no recovery? No observation translated that committed setting change into the server lifecycle's desired state.
4. Why could an agent be directed incorrectly? The command used persisted configuration rather than the server's active listener port.

**Root cause:** The Settings UI treated submit as the only port-commit signal and displayed the persisted draft as if it were a confirmed listener address.

**Defect type:** Missing state synchronization / UI lifecycle integration.

**Contributing factors:** The asynchronous lifecycle coalescer was added after the original UI behavior; it supported safe convergence but was not wired to all TextField commit paths.

### Phase 4 — Solution and verification plan

A small, testable coordinator/state object coalesces committed port values before sending them to `MCPServer.start(port:)`. The view observes the binding through `onChange`, removes the duplicate `onSubmit` restart route, cancels pending work when the server is disabled, and flushes a committed pending value when the MCP section disappears. Setup is rendered only from `MCPServer.activePort` while enabled.

This preserves invalid-port behavior (`start(port:)` transitions to invalid and releases any listener), prevents disabled settings edits from starting a listener, and lets the existing lifecycle coordinator serialize final restart work.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPPortChangeCoordinator.swift` — Added pure `MCPPortChangeState` plus a MainActor debounce coordinator that drops disabled work, deduplicates the latest committed port, flushes teardown work, and delegates application to the existing lifecycle coordinator.
- `Transit/Transit/MCP/MCPServer.swift` — Exposed `activePort` from the listener owned by the lifecycle coordinator.
- `Transit/Transit/Views/Settings/SettingsView.swift` — Replaced submit-only restart behavior with observed committed-port scheduling; cancellation on disable; teardown flushing; and active-port setup rendering.
- `Transit/TransitTests/MCPPortChangeCoordinatorTests.swift` — Added state and live loopback listener regression coverage.
- `specs/mcp-server/implementation.md` — Marked the obsolete port-change limitation as resolved.

**Approach rationale:** Reusing `MCPServer.start(port:)` preserves its single desired-state reconciliation path, including graceful listener handoff and invalid-port handling. A separate coordinator only manages UI timing and does not duplicate listener lifecycle logic.

**Alternatives considered:**
- Explicit Apply button — rejected because it retains a persisted-but-not-running configuration state and adds an avoidable user action.
- Restart solely from `onSubmit` — rejected because focus loss and Settings closure commit bindings without submitting.
- Render setup from the persisted port — rejected because it can advertise an address before the corresponding listener is active.

## Regression Test

**Test file:** `Transit/TransitTests/MCPPortChangeCoordinatorTests.swift`

**Test names:**
- `committedPortQueuesOnlyTheLatestDistinctEnabledValue`
- `disabledServerDoesNotQueuePortChangeOrStartLater`
- `setupCommandUsesActiveListenerPortUntilReplacementIsLive`
- `focusLossPortCommitReplacesLiveListenerWithoutSubmit`

**What they verify:** The pure state deduplicates/coalesces enabled commits, disabled changes cannot start later, setup presentation follows the active listener, and a focus-loss-style commit moves a live loopback listener without a Return submission.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPPortChangeCoordinator.swift` | New testable port state and coordinator. |
| `Transit/Transit/MCP/MCPServer.swift` | Exposes active listener port. |
| `Transit/Transit/Views/Settings/SettingsView.swift` | Observes committed ports and renders the active endpoint. |
| `Transit/TransitTests/MCPPortChangeCoordinatorTests.swift` | State and live-listener regressions. |
| `specs/mcp-server/implementation.md` | Documents resolved behavior. |

## Verification

**Automated:**
- [x] Regression tests were red before implementation: `make test-quick` failed because the new coordinator/state and active-port contract did not exist.
- [x] Regression tests pass: `make test-quick`.
- [x] Strict lint and the ModelContainer ownership guard pass: `make lint`.
- [ ] Full iOS suite is inconclusive: two `make test` attempts timed out. The second reached execution and reported unrelated UI failures in `testClearAll`, `testEditViewPreservesTaskMilestone`, and `testDataMaintenanceGoldenPath` before timeout; T-1821 is compiled only on macOS.

**Manual verification:**
- The live loopback regression starts the server, simulates a focus-loss committed port without `onSubmit`, flushes the coordinator, proves the replacement port accepts connections, and proves the old port is released.

## Prevention

- Route observable settings commits through the owning lifecycle coordinator rather than control-specific submission handlers.
- Render connection instructions from confirmed runtime state when an asynchronous transition can lag persisted configuration.
- Cover focus-loss commits and teardown paths in addition to Return submission.

## Related

- Transit task T-1821
- Existing lifecycle hardening T-1826
