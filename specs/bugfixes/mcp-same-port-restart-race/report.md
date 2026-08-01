# Bugfix Report: MCP Same-Port Restart Race

**Date:** 2026-08-02
**Status:** Fixed

## Description of the Issue

Restarting the embedded MCP server on its configured port, or quickly toggling it off and on, can leave the server stopped with an address-in-use bind failure.

**Reproduction steps:**
1. Start the MCP server and wait for it to accept requests on its configured loopback port.
2. Submit the same port again, or toggle the server off and immediately back on.
3. Observe that the replacement Hummingbird application can fail to bind because the cancelled listener has not released the socket yet.

**Impact:** MCP clients lose access until a later manual retry or app restart. The failure is timing-dependent and is easiest to trigger from Settings, which currently performs `stop()` and `start()` synchronously in one submit action.

## Investigation Summary

The MCP server lifecycle and every caller were inspected using the repository history, current source, tests, Hummingbird package configuration, and project MCP notes.

- **Symptoms examined:** same-port restart and rapid off/on can produce `EADDRINUSE`; the replacement generation then reports stopped.
- **Code inspected:** `MCPServer.swift`, the macOS MCP Settings section, app-launch startup, existing start-failure tests, and all lifecycle call sites.
- **Hypotheses tested:** the generation guard was checked and ruled out as socket serialization—it only suppresses stale UI state writes. Port validation and Hummingbird routing are unrelated to teardown ordering.

### Systematic inspection findings

1. **Integration/timing defect — `MCPServer.stop()`:** requests cancellation but sets `serverTask` to `nil` immediately. No caller can await Hummingbird listener shutdown.
2. **Data-flow defect — `MCPServer.start(port:)`:** creates a detached service task independently of an old task that may still own the configured port.
3. **Integration defect — `SettingsView.macOSMCPSection`:** port submission invokes `stop()` and `start()` back-to-back in the same synchronous closure.
4. **State-management defect:** repeated lifecycle requests have no serialized coordinator or desired state, so they create competing teardown/rebind operations rather than converging on the latest request.

## Discovered Root Cause

Nothing in the shipped code fenced socket ownership. `stop()` cancelled the service task and discarded it synchronously, so a caller could begin a replacement bind while the old Hummingbird listener still held the port.

**Defect type:** Race condition / asynchronous resource lifecycle.

**Five Whys:**
1. Why can the replacement bind fail? The old listening channel can still own the port when the new `Application` binds.
2. Why is it still holding the port? `stop()` only requested cancellation and returned immediately; no caller could await teardown.
3. Why doesn't awaiting the task fix it either? That was the first attempted fix on this branch, and it is insufficient: awaiting cancellation proves task termination, not that Hummingbird's graceful listener-close path ran.
4. Why does cancellation not run that path? `ServiceGroup` responds to task cancellation with `group.cancelAll()`. Listener closure is only guaranteed by Hummingbird's `Server.shutdownGracefully()`, reached when `ServiceGroup.triggerGracefulShutdown()` signals the service's graceful-shutdown manager.
5. Why was the distinction easy to miss? Both the original code and the first fix treated `Application.runService()` completion as the socket-ownership fence, without checking that the dependency has separate cancellation and graceful-shutdown branches.

**Contributing factors:** `isRunning` is optimistic at task launch, and generation guards prevent stale state changes but cannot release an OS socket.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPServer.swift` — retains an `ActiveServer` containing the Hummingbird `ServiceGroup`, run task, port, and logical run ID. Teardown invalidates stale callbacks, calls `triggerGracefulShutdown()`, and awaits the exact group run task before a replacement can bind. No fixed delay or polling is used for teardown. The group sets `maximumGracefulShutdownDuration` so a request that never completes cannot suspend `run()` indefinitely and wedge the single lifecycle task, and installs no `gracefulShutdownSignals` — `runService()`'s SIGTERM/SIGINT default permanently changes the process signal disposition, which a GUI app should not do. `isRunning` is derived from the active listener rather than tracked separately.
- `Transit/Transit/Views/Settings/SettingsView.swift` — submits enabled-state changes asynchronously through one `scheduleMCP(_:)` entry point and uses the explicit same-port `restart(port:)` operation on port submission. The view tracks no request state: `MCPServer` already converges on its latest desired state, so there is nothing useful for the view to cancel.
- `Transit/Transit/TransitApp.swift` — awaits the serialized startup operation from the scene task.
- `Transit/TransitTests/MCPServerLifecycleTests.swift` — exercises real loopback listener release, 20 serialized same-port restart repetitions, different-port restart, overlapping rapid off/on requests, a bind failure against an occupied port, and an invalid-port request releasing a running listener. The free-port probe sets `SO_REUSEADDR`, matching what SwiftNIO sets on its listening socket, so a connection left in `TIME_WAIT` by the readiness probe cannot masquerade as an unreleased listener.
- `Transit/TransitTests/MCPServerStartFailureTests.swift` — awaits the async lifecycle API while preserving invalid-port and error-clearing coverage.

**Approach rationale:** The desired-state loop serializes logical transitions, while explicit `ServiceGroup` ownership supplies the correct resource fence: signal graceful shutdown, then await `run()` completion. Requests arriving during teardown still replace stale targets rather than creating competing listeners.

**Alternatives considered:**
- Add a fixed delay between stop and start — rejected because socket teardown time is not deterministic.
- Cancel and await `Application.runService()` — rejected because Service Lifecycle's cancellation branch is distinct from Hummingbird's graceful listener-close branch.
- Keep generation guards only — rejected because they suppress stale UI updates but do not serialize OS socket ownership.
- Queue every request independently — rejected because bursts would perform unnecessary stop/start cycles instead of converging on the latest state.

## Regression Test

**Test file:** `Transit/TransitTests/MCPServerLifecycleTests.swift`

**Test names:**
- `stopReturnsOnlyAfterListenerReleasesPort`
- `samePortRestartWaitsForOldListenerTeardown` (20 repetitions)
- `differentPortRestartReleasesOldListenerBeforeBindingNewOne`
- `rapidOffOnRequestsCoalesceWithoutAddressInUse`
- `lifecycleConfigurationBoundsShutdownWithoutSignalTraps`
- `gracefulShutdownTimeoutEscalatesToCancellation`
- `reusableBindProbeDistinguishesLiveListenerFromReleasedPort`
- `startOnOccupiedPortSurfacesBindFailure`
- `invalidPortRequestReleasesRunningListener`

**What they verify:** A real loopback Hummingbird listener releases its old port before stop/restart returns, remains reachable after same-port and different-port restart, and converges after a burst of off/on requests without an address-in-use start error. The lifecycle policy has a finite shutdown duration and no process signal traps, and its timeout escalates a non-graceful service to cancellation. The reusable bind probe still rejects a live listener but accepts the released port after a readiness connection. A port held by an unrelated listener surfaces the asynchronous bind failure through `startError` instead of reporting a running server, and an invalid-port request tears the previous listener down rather than returning early.

**Known gap:** the burst test asserts convergence, not the coalescing mechanism — a FIFO queue that performed every transition would pass it too. Deterministically forcing a stop to win a race against an in-flight restart is not expressible through the public API, so that ordering is unverified.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPServer.swift` | Async serialized lifecycle with explicit `ServiceGroup` graceful teardown |
| `Transit/Transit/MCP/MCPServerLifecycleConfiguration.swift` | Bounded graceful-shutdown and no-signal service-group policy |
| `Transit/Transit/MCP/MCPServerDecodeTypes.swift` | Decode helper types moved out to preserve the source file length limit, still nested in `MCPServer` |
| `Transit/Transit/Views/Settings/SettingsView.swift` | Safe enabled/restart task integration |
| `Transit/Transit/TransitApp.swift` | Awaited app-launch startup |
| `Transit/TransitTests/MCPServerLifecycleTests.swift` | Live loopback regression coverage |
| `Transit/TransitTests/MCPServerStartFailureTests.swift` | Async lifecycle API coverage |
| `docs/agent-notes/mcp-server.md` | Serialized lifecycle architecture note |
| `CHANGELOG.md` | Unreleased fix entry |
| `specs/bugfixes/mcp-same-port-restart-race/report.md` | Investigation and verification record |
| `specs/bugfixes/mcp-same-port-restart-race/implementation.md` | Three-level implementation explanation |

## Verification

**Automated:**
- [x] Focused `MCPServerLifecycleTests` pass
- [x] `make test-quick` passes
- [x] `make test` passes
- [x] `make test-ui` passes
- [x] `make build` passes for iOS and macOS
- [x] `make lint` passes

**Manual verification:**
- The live-loopback regression starts Hummingbird on an ephemeral port, immediately verifies the port is bindable after awaited stop, restarts on the same port, and issues overlapping off/on requests. All paths remain reachable with no address-in-use error.

## Prevention

- Verify framework cancellation and graceful-shutdown paths separately; task completion is not automatically a resource-release guarantee.
- Retain the Hummingbird `ServiceGroup`, call `triggerGracefulShutdown()`, and await its `run()` task before rebinding.
- Route all start/stop/restart requests through one serialized desired-state coordinator.
- Keep UI callers from composing lifecycle primitives into unsafe stop/start sequences.
- Bound any teardown that a single serialized coordinator awaits. An unbounded graceful shutdown converts one stuck connection into a permanently wedged lifecycle.
- Construct `ServiceGroup` explicitly rather than inheriting `runService()`'s defaults; its SIGTERM/SIGINT traps are wrong for a GUI app.
- Give socket probes in tests the same options as the code under test (`SO_REUSEADDR`), or the probe fails on states production tolerates.

## Related

- Transit T-1826
