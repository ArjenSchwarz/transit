# Bugfix Report: MCP Port Listener Alignment

**Date:** 2026-08-05
**Status:** Investigating

## Description of the Issue

The macOS MCP Settings port field persists a numeric value when the field commits, including when it loses focus or Settings closes. The running MCP listener is restarted only by the TextField's `onSubmit` handler. Consequently, a focus-loss commit persists and advertises a new port while the embedded MCP server remains bound to its previous port.

**Reproduction steps:**
1. Enable the MCP server and wait for it to listen on its configured port.
2. Enter a different valid port in Settings.
3. Click elsewhere or close Settings without pressing Return.
4. Observe that the setup command uses the persisted new port while the live listener remains on the old port.

**Impact:** Agents following the displayed setup command cannot connect until a later restart or app relaunch. The persisted configuration and active runtime state are misleadingly divergent.

## Investigation Summary

### Phase 1 — Initial overview

Expected behavior is that every committed enabled-server port value converges through the existing serialized MCP lifecycle coordinator, regardless of whether commit came from Return or focus loss. The setup command must describe the active listener, not an un-applied draft.

Actual behavior is limited to `TextField.onSubmit`, so focus-loss commits receive no lifecycle request. No runtime error is emitted because the old listener remains healthy.

### Phase 2 — Systematic inspection

- `Transit/Transit/Views/Settings/SettingsView.swift` binds the port directly to `MCPSettings.port` and calls `scheduleMCP(.restart)` only from `onSubmit`.
- `Transit/Transit/MCP/MCPSettings.swift` persists every binding update through `didSet`, independently of listener state.
- `Transit/Transit/MCP/MCPServer.swift` already has a desired-state coordinator: `start(port:)` validates ports, coalesces duplicate desired states, tears down old listeners before binding a replacement, and stops for invalid ports.
- `SettingsView` renders the setup command directly from the persisted `mcpSettings.port`, which can differ from the active listener during an un-applied or in-flight change.

### Phase 3 — Root cause analysis

1. Why does focus loss leave the old listener bound? The lifecycle request exists only in `onSubmit`.
2. Why does the displayed command change anyway? The `TextField` binding commits directly to UserDefaults-backed `MCPSettings.port`.
3. Why is there no recovery? No observation translates that committed setting change into the server lifecycle's desired state.
4. Why can an agent be directed incorrectly? The command uses persisted configuration rather than the server's active listener port.

**Root cause:** The Settings UI treats submit as the only port-commit signal and displays the persisted draft as if it were a confirmed listener address.

**Defect type:** Missing state synchronization / UI lifecycle integration.

**Contributing factors:** The asynchronous lifecycle coalescer was added after the original UI behavior; it supports safe convergence but was not wired to all TextField commit paths.

### Phase 4 — Solution and verification plan

Use a small, testable coordinator/state object to coalesce committed port values before sending them to the existing `MCPServer.start(port:)` desired-state coordinator. Observe the binding through `onChange`, remove the duplicate `onSubmit` restart route, cancel pending work when the server is disabled, and flush a committed pending value on view teardown. Render setup only from `MCPServer.activePort` while enabled.

This preserves existing invalid-port behavior (`start(port:)` transitions to invalid and releases any listener), prevents disabled settings edits from starting a listener, and lets the lifecycle coordinator serialize final restart work.

## Resolution for the Issue

Pending implementation.

## Regression Test

**Test files:**
- `Transit/TransitTests/MCPPortChangeCoordinatorTests.swift`
- `Transit/TransitTests/MCPServerLifecycleTests.swift`

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
| `Transit/Transit/Views/Settings/SettingsView.swift` | Observe committed port changes and present the active listener endpoint. |
| `Transit/Transit/MCP/MCPServer.swift` | Expose the active listener port to Settings. |
| `Transit/Transit/MCP/MCPPortChangeCoordinator.swift` | New testable port-change state and debounced coordinator. |
| `Transit/TransitTests/MCPPortChangeCoordinatorTests.swift` | Coordinator-state regressions. |
| `Transit/TransitTests/MCPServerLifecycleTests.swift` | Focus-loss live-listener regression. |

## Verification

**Automated:**
- [x] Regression tests are red before implementation: `make test-quick` fails because the new coordinator/state and active-port contract do not exist.
- [ ] Regression tests pass
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Pending implementation.

## Prevention

- Route observable settings commits through the owning lifecycle coordinator rather than control-specific submission handlers.
- Render connection instructions from confirmed runtime state when an asynchronous transition can lag persisted configuration.
- Cover focus-loss commits and teardown paths in addition to Return submission.

## Related

- Transit task T-1821
- Existing lifecycle hardening T-1826
