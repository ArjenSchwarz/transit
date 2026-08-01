# T-1826 MCP Lifecycle Fix — Implementation Explanation

## Beginner Level

### What Changed / What This Does

Transit contains a small web server that lets local MCP clients communicate with the app. Previously, turning that server off only *asked* it to stop and immediately started a replacement. The old server could still be holding the network port, so the new server sometimes failed with "address already in use."

The server now has one lifecycle coordinator. It remembers the latest requested state—stopped, invalid port, or running on a particular port—and handles requests one at a time. Each running listener keeps both its Hummingbird service group and the task running that group. Before starting a replacement, Transit tells the group to shut down gracefully and waits for that run task to finish.

### Why It Matters

Same-port changes and quick off/on toggles now leave MCP available instead of randomly stopping it. Users no longer need to retry the setting or restart Transit after this race.

### Key Concepts

- **Task cancellation:** stops asynchronous tasks, but does not necessarily run a framework's graceful resource cleanup.
- **Graceful shutdown:** tells Hummingbird to close its listening channel through its documented service lifecycle.
- **Awaiting teardown:** waiting for the gracefully shutting-down service group to finish before reusing the network port.
- **Converging on the latest request:** replacing several intermediate requests with the newest one, like keeping only the final destination entered into navigation.
- **Timeout as a safety valve:** waiting forever is not a safe default when everything else queues behind that wait.

## Intermediate Level

### Changes Overview

`MCPServer` exposes async `start(port:)`, `stop()`, and `restart(port:)`. Requests update a `DesiredState`; a single MainActor lifecycle task reconciles that state. `ActiveServer` keeps the listener's port, logical run ID, Hummingbird `ServiceGroup`, and detached task running that group as one ownership record. `isRunning` is derived from whether an `ActiveServer` exists rather than tracked as a second field.

`SettingsView` submits requests through one `scheduleMCP(_:)` entry point taking a `.start` / `.stop` / `.restart` case, and holds no request state of its own. `TransitApp` awaits startup from its scene task. The loopback suite covers listener release, 20 parameterized same-port restarts, different-port restart, rapid overlapping requests, a bind failure against an occupied port, an invalid-port request tearing down a running listener, bounded shutdown escalation, empty process-signal configuration, and a reusable bind probe distinguishing a live listener from a released port.

### Implementation Approach

The reconciliation loop snapshots the desired state, applies it, and checks whether another request arrived during an `await`. If so, it loops using the newer state. Teardown invalidates the old completion callback, clears active identity, calls `ServiceGroup.triggerGracefulShutdown()`, and awaits the group's detached `run()` task. Hummingbird's graceful signal reaches `Server.shutdownGracefully()`, which closes the listening channel before `run()` completes.

This is deliberately different from cancelling the run task. Swift Service Lifecycle responds to task cancellation with `group.cancelAll()`; that path does not provide Hummingbird's listener-release guarantee even when the cancelled task is awaited.

A logical run ID distinguishes an explicit restart from an idempotent repeated start. Repeated starts on the active/requested port reuse the run ID, while restart always allocates a new one. This avoids unnecessary churn but preserves explicit restart semantics.

The `ServiceGroup` is constructed explicitly rather than through `Application.runService()`, which changes two defaults. `maximumGracefulShutdownDuration` is set so the group escalates to cancellation instead of waiting indefinitely for accepted connections to close. `gracefulShutdownSignals` is left empty: `runService()` would trap SIGTERM/SIGINT, which sets those signals to `SIG_IGN` process-wide and permanently, and a GUI app has no use for them when teardown is driven by `triggerGracefulShutdown()`.

### Trade-offs

The server keeps a small amount of additional state (`desiredState`, `ActiveServer`, lifecycle task, generation) to make ordering and ownership explicit. This is preferable to delays, which cannot guarantee socket release, and to a FIFO transition queue, which would perform every obsolete toggle instead of converging on the latest state.

The shutdown timeout trades a small worst-case data loss (a client's in-flight request cut short after five seconds) for the guarantee that the coordinator always makes progress. Since the coordinator is a single serialized task, an unbounded wait would not merely delay one stop — it would stall every later start, stop, and restart with no way to recover short of quitting the app.

## Expert Level

### Technical Deep Dive

The coordinator relies on MainActor reentrancy deliberately. `request(_:)` synchronously publishes a new target before awaiting the shared lifecycle task. While `tearDownCurrentServer()` awaits graceful shutdown, later MainActor callers can overwrite `desiredState`; after teardown, the snapshot equality guard prevents stale rebinding and the loop applies only the newest target. The exit sequence — `guard desiredState == target`, `lifecycleTask = nil`, `return` — contains no suspension point, so no request can be published into a coordinator that has already decided to stop.

Two identities solve different races. `runID` expresses desired listener identity and makes an explicit same-port restart observably different from an idempotent start. `serverGeneration` fences detached completion callbacks. Because teardown always awaits the run task, the callback's `activeServer = nil` write is a no-op by the time it runs; what the fence actually suppresses is a bogus `startError`. If teardown runs before the detached task reaches `serviceGroup.run()`, the group transitions straight to `.finished` and the subsequent `run()` throws `ServiceGroupError.alreadyFinished` — which, unfenced, would surface as "Could not start server on port N" for a server the user just asked to stop. Incrementing the generation *before* triggering shutdown is what makes that safe.

A spontaneous bind failure clears active identity but intentionally leaves the desired running state. A later start request on the same port schedules reconciliation again and can retry. Invalid ports are represented as desired state rather than an early return so an invalid restart still tears down the previous listener and reports the validation error deterministically; `invalidPortRequestReleasesRunningListener` pins that behaviour.

### Architecture Impact

Lifecycle ownership is contained in `MCPServer`; UI code requests outcomes rather than composing primitives. The async API makes graceful listener teardown part of the contract, while the internal desired-state loop prevents callers from creating concurrent Hummingbird applications. Because the server coalesces internally, callers need no request bookkeeping — `SettingsView` deliberately fires and forgets. Routing and tool dispatch remain unchanged.

`MCPServer.swift` sits close to the 400-line file-length limit, which is why the decode result types live in `MCPServerDecodeTypes.swift`. They stay nested in an `extension MCPServer` there rather than at module scope, so `DecodeOutcome` and `BatchElement` do not occupy those generic names app-wide.

### Potential Issues

`isRunning` remains optimistic: it becomes true when the listener task launches, not when the bind succeeds. An asynchronous bind failure corrects it through the generation-checked callback, and `startOnOccupiedPortSurfacesBindFailure` now verifies that path against a real occupied port. Callers that need certainty must observe `startError` or probe the port, as the tests do.

The live tests select an ephemeral port by binding port zero and releasing it before Hummingbird starts, which has a theoretical external TOCTOU window but is suitably narrow for serialized local tests. The free-port probe sets `SO_REUSEADDR` to match SwiftNIO's listening socket; without it, a connection the readiness check left in `TIME_WAIT` would report `EADDRINUSE` and fail the test against behaviour production tolerates.

Coalescing is opportunistic, not guaranteed: only requests landing during a single `await` window collapse. A burst still converges, bounded by the request count, but may perform more than one teardown/rebind cycle along the way.

## Completeness Assessment

- **Fully implemented:** async start/stop/restart, explicit graceful shutdown plus awaited group completion, bounded shutdown duration, no process-wide signal traps, active-listener ownership, stale-callback fencing, latest-state convergence, safe Settings and app-start integration, invalid-port behaviour, and live regressions for listener release, 20 same-port repetitions, different-port restart, rapid toggling, occupied-port bind failure, invalid-port teardown, timeout escalation, empty signal configuration, and reusable bind-probe behavior.
- **Partially implemented:** none.
- **Missing:** none for T-1826's scope. Two behaviours are verified indirectly rather than directly — the coalescing *mechanism* (the burst test asserts convergence, which a FIFO queue would also satisfy) and a stop winning a race against an in-flight restart, which the public API cannot deterministically sequence. `SettingsView`'s scheduling helpers remain untested; they are now thin enough that the logic under test lives entirely in `MCPServer`.
