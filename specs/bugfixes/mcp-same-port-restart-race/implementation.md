# T-1826 MCP Lifecycle Fix — Implementation Explanation

## Beginner Level

### What Changed / What This Does

Transit contains a small web server that lets local MCP clients communicate with the app. Previously, turning that server off only *asked* it to stop and immediately started a replacement. The old server could still be holding the network port, so the new server sometimes failed with “address already in use.”

The server now has one lifecycle coordinator. It remembers the latest requested state—stopped, invalid port, or running on a particular port—and handles requests one at a time. Before starting a replacement, it cancels the old server and waits until the old task has fully finished.

Settings also uses an explicit restart operation instead of issuing separate stop and start calls.

### Why It Matters

Same-port changes and quick off/on toggles now leave MCP available instead of randomly stopping it. Users no longer need to retry the setting or restart Transit after this race.

### Key Concepts

- **Task cancellation:** a request for asynchronous work to stop; it does not mean the work has already stopped.
- **Awaiting teardown:** waiting until cleanup is complete and the network port has actually been released.
- **Coalescing:** replacing several intermediate requests with the latest one, like keeping only the final destination entered into navigation.

## Intermediate Level

### Changes Overview

`MCPServer` now exposes async `start(port:)`, `stop()`, and `restart(port:)`. Requests update a `DesiredState`; a single MainActor lifecycle task reconciles that state. The active detached Hummingbird task is tracked with its port, logical run ID, and callback generation.

`SettingsView` stores one cancellable request task. Toggle changes schedule async start/stop operations, while port submission schedules `restart(port:)`. `TransitApp` awaits startup from its scene task. Existing invalid-port tests were migrated to the async API, and new loopback tests cover listener release, same-port restart, and rapid overlapping requests.

### Implementation Approach

The reconciliation loop snapshots the desired state, applies it, and checks whether another request arrived during an `await`. If so, it loops using the newer state. Teardown first invalidates the old completion callback, clears active identity, cancels the service task, and awaits `task.value`. Hummingbird’s `runService()` completes only after its graceful-shutdown path releases the listening channel, making this await the socket ownership fence.

A logical run ID distinguishes an explicit restart from an idempotent repeated start. Repeated starts on the active/requested port reuse the run ID, while restart always allocates a new one. This avoids unnecessary churn but preserves explicit restart semantics.

### Trade-offs

The server keeps a small amount of additional state (`desiredState`, active port/run ID, lifecycle task, generation) to make ordering explicit. This is preferable to delays, which cannot guarantee socket release, and to a FIFO transition queue, which would perform every obsolete toggle instead of converging on the latest state.

## Expert Level

### Technical Deep Dive

The coordinator relies on MainActor reentrancy deliberately. `request(_:)` synchronously publishes a new target before awaiting the shared lifecycle task. While `tearDownCurrentServer()` awaits the detached service task, later MainActor callers can overwrite `desiredState`; after teardown, the snapshot equality guard prevents stale rebinding and the loop applies only the newest target.

Two identities solve different races. `runID` expresses desired listener identity and makes an explicit same-port restart observably different from an idempotent start. `serverGeneration` fences detached completion callbacks: teardown increments it before cancellation, so a stale callback cannot clear state belonging to a replacement listener. The detached task captures only the handler and a MainActor callback, preserving Swift 6 isolation rules.

A spontaneous bind failure clears active identity but intentionally leaves the desired running state. A later start request on the same port schedules reconciliation again and can retry. Invalid ports are represented as desired state rather than an early return so an invalid restart still tears down the previous listener and reports the validation error deterministically.

### Architecture Impact

Lifecycle ownership is now contained in `MCPServer`; UI code requests outcomes rather than composing primitives. The async API makes teardown completion part of the contract, while the internal desired-state loop prevents callers from creating concurrent Hummingbird applications. Routing and tool dispatch remain unchanged.

### Potential Issues

`isRunning` remains optimistic at listener task launch, matching previous behavior; asynchronous bind errors still correct it through the generation-checked callback. The live tests select an ephemeral port by binding port zero and releasing it before Hummingbird starts, which has a theoretical external TOCTOU window but is suitably narrow for serialized local tests.

## Completeness Assessment

- **Fully implemented:** async start/stop/restart, cancellation plus awaited teardown, stale-callback fencing, latest-state coalescing, safe Settings and app-start integration, invalid-port behavior, and live listener-release, same-port, different-port, and rapid-toggle regressions.
- **Partially implemented:** none.
- **Missing:** none for T-1826’s scope. Listener readiness is still represented optimistically, but that is existing behavior outside this ticket and bind failures remain surfaced through `startError`.
