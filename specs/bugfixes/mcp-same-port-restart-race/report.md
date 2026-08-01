# Bugfix Report: MCP Same-Port Restart Race

**Date:** 2026-08-02
**Status:** In Progress

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

The lifecycle tracks task identity for UI generation safety but does not own listener teardown as an asynchronous, serialized operation.

**Defect type:** Race condition / asynchronous resource lifecycle.

**Five Whys:**
1. Why does the replacement bind fail? The old listener can still own the port.
2. Why can it still own the port? Task cancellation is cooperative and Hummingbird closes the listener asynchronously.
3. Why does rebinding proceed before close completes? `stop()` discards the task without awaiting its result.
4. Why can Settings trigger that ordering? It calls `stop()` and `start()` synchronously with no lifecycle boundary.
5. Why do repeated requests worsen it? There is no single-flight reconciliation loop that coalesces requests to the latest desired server state.

**Contributing factors:** `isRunning` is optimistic at task launch, and the generation guard prevents stale state changes but cannot serialize ownership of an OS socket.

## Resolution for the Issue

Pending implementation.

## Regression Test

**Test file:** `Transit/TransitTests/MCPServerLifecycleTests.swift`

**Test names:**
- `samePortRestartWaitsForOldListenerTeardown`
- `rapidOffOnRequestsCoalesceWithoutAddressInUse`

**What they verify:** A real loopback Hummingbird listener remains reachable after same-port restart and after a burst of off/on requests, with no address-in-use start error.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/TransitTests/MCPServerLifecycleTests.swift` | Live loopback regression coverage |
| `Transit/Transit/MCP/MCPServer.swift` | Pending serialized lifecycle implementation |
| `Transit/Transit/Views/Settings/SettingsView.swift` | Pending safe restart integration |
| `specs/bugfixes/mcp-same-port-restart-race/report.md` | Investigation and verification record |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Pending implementation.

## Prevention

- Treat cancellation plus awaiting task completion as one listener teardown operation.
- Route all start/stop/restart requests through one serialized desired-state coordinator.
- Keep UI callers from composing lifecycle primitives into unsafe stop/start sequences.

## Related

- Transit T-1826
