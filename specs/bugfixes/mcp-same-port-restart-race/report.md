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

The lifecycle coordinator serialized task completion but used the wrong shutdown signal. Swift Service Lifecycle handles parent task cancellation by cancelling its task group; Hummingbird closes the listening channel in `Server.shutdownGracefully()`, which is driven by the service group's graceful-shutdown manager instead.

**Defect type:** Race condition / asynchronous resource lifecycle.

**Five Whys:**
1. Why can the replacement bind fail after awaited teardown? The old listening channel can still own the port.
2. Why can it still own the port after the wrapper task was cancelled and awaited? Awaiting cancellation proves task termination, not that Hummingbird's graceful listener-close path ran.
3. Why does cancellation not run that path? `ServiceGroup` responds to task cancellation with `group.cancelAll()`.
4. Where is listener closure guaranteed? Hummingbird's `Server.shutdownGracefully()`, reached when `ServiceGroup.triggerGracefulShutdown()` signals the service's graceful-shutdown manager.
5. Why did review miss it? The implementation assumed `Application.runService()` completion itself was the socket ownership fence without verifying the dependency's distinct cancellation and graceful-shutdown branches.

**Contributing factors:** `isRunning` is optimistic at task launch, and generation guards prevent stale state changes but cannot release an OS socket.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPServer.swift` — retains an `ActiveServer` containing the Hummingbird `ServiceGroup`, run task, port, and logical run ID. Teardown invalidates stale callbacks, calls `triggerGracefulShutdown()`, and awaits the exact group run task before a replacement can bind. No fixed delay or polling is used for teardown.
- `Transit/Transit/Views/Settings/SettingsView.swift` — owns one cancellable lifecycle waiter, submits enabled-state changes asynchronously, and uses the explicit same-port `restart(port:)` operation on port submission.
- `Transit/Transit/TransitApp.swift` — awaits the serialized startup operation from the scene task.
- `Transit/TransitTests/MCPServerLifecycleTests.swift` — exercises real loopback listener release, 20 serialized same-port restart repetitions, different-port restart, and overlapping rapid off/on requests.
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
- `samePortRestartWaitsForOldListenerTeardown`
- `differentPortRestartReleasesOldListenerBeforeBindingNewOne`
- `rapidOffOnRequestsCoalesceWithoutAddressInUse`

**What they verify:** A real loopback Hummingbird listener releases its old port before stop/restart returns, remains reachable after same-port and different-port restart, and converges after a burst of off/on requests without an address-in-use start error.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPServer.swift` | Async serialized lifecycle with explicit `ServiceGroup` graceful teardown |
| `Transit/Transit/MCP/MCPServerDecodeTypes.swift` | Decode helper types extracted to preserve the source file length limit |
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

## Related

- Transit T-1826
