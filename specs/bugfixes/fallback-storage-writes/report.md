# Bugfix Report: Automation Surfaces Accept Writes To Fallback Storage

**Date:** 2026-07-25
**Status:** Fixed
**Tickets:** T-1818 (MCP surface), T-1836 (App Intents surface)

## Description of the Issue

When Transit's persistent SwiftData store cannot be opened, `ContainerFactory.makeContainer`
returns an in-memory fallback container so the app still launches. `TransitApp.init()` then
proceeded exactly as if nothing had happened: it built `TaskService`, `ProjectService`,
`CommentService`, `MilestoneService` and `DisplayIDMaintenanceService` on that container,
registered them with `AppDependencyManager`, and started the MCP server and sync heartbeat.

The only signal that storage was degraded was an in-app SwiftUI alert ("Unable to Load Data").
Automation callers never see that alert, so:

- **T-1818 - MCP:** an MCP client calling `create_task`, `update_task_status`, `update_task`,
  `add_comment`, `create_milestone`, `update_milestone`, `delete_milestone` or
  `reassign_duplicate_display_ids` received an ordinary success payload, complete with a
  `taskId` and `displayId`, for a record that ceased to exist at the next launch.
- **T-1836 - App Intents:** Shortcuts/CLI callers running `CreateTaskIntent`, `UpdateStatusIntent`,
  `UpdateTaskIntent`, `AddCommentIntent`, `CreateMilestoneIntent`, `UpdateMilestoneIntent`,
  `DeleteMilestoneIntent`, `ReassignDuplicateDisplayIDsIntent` or the visual `AddTaskIntent` got
  the same successful-looking results.

**Reproduction steps:**

1. Put the device/Mac in a state where the persistent store cannot be opened (disk full, corrupt
   store, unreadable Application Support directory). `ContainerFactory` logs
   "ModelContainer init failed ... Falling back to in-memory store" and returns a non-nil
   `ContainerOutcome.error`.
2. Launch Transit. The in-app alert appears; dismiss it (or never see it - the app may be
   launched in the background by an intent).
3. From a script or agent, call the MCP tool `create_task`, or run the `Transit: Create Task`
   shortcut.
4. Observe a normal success response with a `taskId`.
5. Quit and relaunch Transit. The task is gone, and nothing in the automation transcript
   indicates the write ever failed.

**Impact:** High. Silent data loss on the two surfaces used for unattended automation. Because
the response is a well-formed success, callers have no way to detect the loss and will happily
build on top of the phantom record (assigning milestones, adding comments, reporting the work as
done). The MCP path is worse than the intents path only in that agents call it far more often.

## Investigation Summary

- **Symptoms examined:** Successful mutation responses on both automation surfaces with no
  corresponding durable record after relaunch.
- **Code inspected:**
  - `Transit/Transit/Services/ContainerFactory.swift` - confirmed the fallback path returns a
    fully usable in-memory `ModelContainer` alongside the originating error.
  - `Transit/Transit/TransitApp.swift` - confirmed `containerResult.error` is consumed for
    exactly two things: the alert `@State` and skipping CloudKit schema initialisation. Service
    construction, `AppDependencyManager` registration and MCP startup all proceed unconditionally.
  - `Transit/Transit/MCP/MCPToolHandler.swift` and `Transit/Transit/Intents/**` - confirmed no
    entry point consults storage health; every guard is about argument validation.
- **Hypotheses tested and ruled out:**
  - *The services detect the in-memory container themselves.* They do not - they only hold a
    `ModelContext` and follow the mutate/save/rollback pattern. `save()` succeeds against the
    in-memory store, so there is no error to surface.
  - *`isStoredInMemoryOnly` could be read back off the container as the signal.* Rejected: the
    unit-test host and UI-test scenarios legitimately run in-memory, so that property conflates
    "degraded" with "intentionally ephemeral". The authoritative signal is
    `ContainerOutcome.error`.
  - *The alert is enough.* It is not: an App Intent can launch the app into the foreground and a
    Shortcut can complete before a human ever reads the alert, and the MCP server serves requests
    while the alert is on screen.

## Discovered Root Cause

`ContainerFactory` reports degraded storage through `ContainerOutcome.error`, but that value is
only ever routed to the UI. There is no machine-readable persistence-availability signal for
non-UI callers, so the automation entry points cannot distinguish a durable write from one made
against a throwaway container.

**Defect type:** Missing precondition / error signal not propagated across a layer boundary.

**Why it occurred:** The fallback was designed as a *user experience* mitigation ("the app
remains usable") at a point in Transit's life when the app was the only surface. MCP and App
Intents were added later, reusing the same services and the same `mainContext`, and inherited the
assumption that a caller who needs to know about degraded storage will see the alert.

**Contributing factors:**

- Failure is invisible in normal testing: the fallback container behaves identically to a real
  one for every operation, so no test could catch this without deliberately injecting a
  container-creation failure.
- The two surfaces were filed as separate tickets, which invited two separate ad-hoc mechanisms.

## Resolution for the Issue

One persistence-availability signal, derived once from the `ContainerFactory` outcome, gating
both surfaces.

**Changes made:**

- `Transit/Transit/Services/PersistenceAvailability.swift` (new) - `@MainActor final class`
  holding `isFallbackStorageActive`, plus `update(from: ContainerFactory.ContainerOutcome)` (the
  single derivation: `outcome.error != nil`) and the stable `unavailableHint` message returned to
  callers on both surfaces. `shared` is the instance consulted at runtime.
- `Transit/Transit/TransitApp.swift` - `PersistenceAvailability.shared.update(from: containerResult)`
  immediately after the container is created, and the instance is passed to `MCPToolHandler`.
- `Transit/Transit/MCP/MCPToolHandler.swift` - new `persistence` init parameter (defaulting to
  `.shared`) and a single gate in `handleToolCall`, before dispatch. `mutatingToolNames` is
  derived by subtracting a small read-only allow-list from the full tool list, so a newly added
  tool is treated as mutating without a second edit. Rejected calls return an MCP tool error
  (`isError: true`) carrying `PersistenceAvailability.unavailableHint`.
- `Transit/Transit/Intents/IntentHelpers.swift` - `fallbackStorageErrorJSON(_:)` returns the
  `INTERNAL_ERROR` JSON envelope while fallback storage is active, `nil` otherwise. All JSON
  intents share this one construction.
- Mutating App Intents - each `execute(...)` takes `persistence: PersistenceAvailability = .shared`
  and returns/throws immediately when fallback storage is active:
  `CreateTaskIntent`, `UpdateStatusIntent`, `UpdateTaskIntent`, `CreateMilestoneIntent`,
  `UpdateMilestoneIntent`, `DeleteMilestoneIntent`, `ReassignDuplicateDisplayIDsIntent`
  (JSON `INTERNAL_ERROR`), and `AddCommentIntent` / visual `AddTaskIntent`
  (`VisualIntentError.persistenceUnavailable`, whose `code` is also `INTERNAL_ERROR`).
- `Transit/Transit/Intents/Visual/VisualIntentError.swift` - new `persistenceUnavailable` case for
  the two intents that throw rather than return JSON.

**Approach rationale:**

- *One signal, two surfaces.* Both tickets share a root cause, so they share a mechanism. The
  derivation `outcome.error != nil` exists in exactly one place (`update(from:)`), called by
  `TransitApp` at launch and by the tests with an injected-failure outcome.
- *`INTERNAL_ERROR` rather than a new code.* The request is well-formed; Transit simply cannot
  carry it out. That is what `INTERNAL_ERROR` already means in Transit's documented intent error
  vocabulary, and reusing it keeps existing CLI callers' error handling valid. The hint string is
  stable so scripted callers can match on it.
- *MCP tool error rather than a JSON-RPC protocol error.* Per MCP convention, tool execution
  failures belong in the result with `isError: true` so the calling model sees them; protocol
  errors are for malformed envelopes.
- *Reject mutations rather than refuse to start the MCP server.* T-1818 offered both. A dead port
  is indistinguishable from a misconfigured server, a crashed app, or a wrong port number - the
  client learns nothing. A per-call error names the actual problem and the remedy.
- *Reads stay available.* A read cannot destroy data, and degraded-mode introspection is useful
  while diagnosing the failure. A read can still mislead (an empty `query_tasks` looks like an
  empty database), but every action a caller could take on the strength of a misleading read is
  itself blocked by the same gate, so the harmful chain is broken at the write.
- *Fail-safe tool classification.* The MCP gate blocks everything except an explicit read-only
  allow-list. Adding a tool without thinking about this gate leaves it blocked, not exposed.
- *The interactive UI is deliberately untouched.* A person who has seen the alert has made an
  informed choice to keep working; blocking the UI too would turn a degraded app into a dead one,
  and the tickets scope the fix to the automation surfaces.

**Alternatives considered:**

- **Gate inside the services** (`TaskService.createTask` etc. throw when storage is degraded) -
  one gate for everything, but it also breaks every UI write path, contradicting the fallback's
  stated purpose of keeping the app usable, and it would have required editing view code owned by
  other in-flight work.
- **Derive the signal from `container.configurations.first?.isStoredInMemoryOnly`** - no new type,
  but it cannot distinguish degraded storage from the intentional in-memory containers used by the
  unit-test host and the UI-test scenarios.
- **Disable the MCP server and unregister the intent dependencies at launch** - the strongest
  possible guarantee, but the failure surfaces as connection refused / "no such shortcut", which
  is far harder to diagnose than an explicit error, and it removes read access as collateral.
- **A new `STORAGE_UNAVAILABLE` error code** - more precise, but it expands the documented error
  vocabulary in CLAUDE.md and the intent schemas, and both tickets explicitly asked for
  `INTERNAL_ERROR`.

## Regression Test

**Test files:**

- `Transit/TransitTests/FallbackOutcomeFixture.swift` - derives `PersistenceAvailability` from a
  real `ContainerFactory.makeContainer` call whose `makePrimary` closure throws (the same
  injectable-failure hook `ModelContainerFallbackTests` uses), mirroring `TransitApp.init()`
- `Transit/TransitTests/FallbackStorageIntentRejectionTests.swift` (T-1836)
- `Transit/TransitTests/MCPFallbackStorageRejectionTests.swift` (T-1818, macOS-only)

Both suites take their signal from the fixture and run their data assertions against isolated
`TestModelContainer` contexts. The fixture builds the degraded outcome exactly once per test
process on purpose: `ContainerFactory`'s fallback creates its `ModelConfiguration` without a name,
so every fallback container in a process shares one in-memory store identity. Creating them per
test leaks data between tests (the reason `TestModelContainer` names its configurations uniquely)
and can trip the `try!` inside `ContainerFactory`, which takes the whole test host down. Each
suite also runs the same operations against a *successful* `ContainerFactory` outcome, which is
the pre-fix behaviour and demonstrates the gate is condition-specific rather than a blanket
refusal.

**What they verify:**

- Every mutating App Intent returns `{"error":"INTERNAL_ERROR","hint":<shared hint>}` (or throws
  `VisualIntentError.persistenceUnavailable`) while fallback storage is active, and the store is
  left untouched - no task, milestone, comment, status change or priority change is applied.
- Every mutating MCP tool returns `isError: true` with the same hint, and `create_task` /
  `update_task_status` leave the store untouched.
- Read intents (`QueryTasksIntent`, `ScanDuplicateDisplayIDsIntent`) and read-only MCP tools
  (`query_tasks`, `query_milestones`, `get_projects`, `scan_duplicate_display_ids`) still work.
- With a healthy container, `CreateTaskIntent` and MCP `create_task` still succeed and persist.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/PersistenceAvailability.swift` | New - the single persistence-availability signal and shared caller-facing hint |
| `Transit/Transit/TransitApp.swift` | Derives the signal from `containerResult`; passes it to `MCPToolHandler` |
| `Transit/Transit/MCP/MCPToolHandler.swift` | `persistence` dependency; single pre-dispatch gate on mutating tools |
| `Transit/Transit/Intents/IntentHelpers.swift` | `fallbackStorageErrorJSON(_:)` - one construction of the rejection envelope |
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Gate |
| `Transit/Transit/Intents/UpdateStatusIntent.swift` | Gate |
| `Transit/Transit/Intents/UpdateTaskIntent.swift` | Gate |
| `Transit/Transit/Intents/CreateMilestoneIntent.swift` | Gate |
| `Transit/Transit/Intents/UpdateMilestoneIntent.swift` | Gate |
| `Transit/Transit/Intents/DeleteMilestoneIntent.swift` | Gate |
| `Transit/Transit/Intents/AddCommentIntent.swift` | Gate (throws) |
| `Transit/Transit/Intents/ReassignDuplicateDisplayIDsIntent.swift` | Gate |
| `Transit/Transit/Intents/Visual/AddTaskIntent.swift` | Gate (throws) |
| `Transit/Transit/Intents/Visual/VisualIntentError.swift` | New `persistenceUnavailable` case |
| `Transit/TransitTests/FallbackOutcomeFixture.swift` | New - derives the signal from a real ContainerFactory failure, once per process |
| `Transit/TransitTests/FallbackStorageIntentRejectionTests.swift` | New - App Intents regression suite |
| `Transit/TransitTests/MCPFallbackStorageRejectionTests.swift` | New - MCP regression suite |

## Verification

**Automated:**

- [x] `make lint` - 0 violations (strict)
- [x] `make test-quick` (macOS, full unit suite including the macOS-only MCP tests) - 1362 passed,
      0 failed, single test host, all 22 new tests green
- [~] `make test` (iOS Simulator) - reached 813 passed / 0 failed, including all 15 new App Intent
      tests, then the `xcodebuild` process wedged after the test phase. This is the environment
      issue described in `docs/agent-notes/build-sandbox-wedge.md`, aggravated by three other
      worktrees running `xcodebuild` concurrently on the same machine (several already wedged at
      0% CPU). Re-run when the machine is quiet. No test failure was observed at any point.
- [ ] `make test-ui` - not run, same environment constraint

**Manual verification:** Not performed - the failure requires an unopenable persistent store,
which the injected-failure tests reproduce more reliably than a manual disk-full setup.

**Note on the first test runs:** the initial versions of the regression suites created a fallback
container per test, which crash-looped the test host (six restarts, ~850 spurious failures).
That was a defect in the tests, not the fix - see the Regression Test section for the cause and
the fixture that resolves it.

## Prevention

- **Route environment degradation through a value, not a UI alert.** When a subsystem falls back
  to a lesser mode, publish that as state something can branch on. An alert only reaches the one
  caller who happens to be a human looking at the screen.
- **Classify new surfaces against existing gates.** `MCPToolHandler.mutatingToolNames` is derived
  by subtraction so a new tool is blocked by default; keep that direction rather than an opt-in
  list of tools to block.
- **When two tickets name the same root cause, fix them together.** Splitting this by surface
  would have produced two independent "is persistence durable?" mechanisms in the same files.

## Related

- Transit tickets T-1818 and T-1836 (this branch closes both)
- `Transit/TransitTests/ModelContainerFallbackTests.swift` - the pre-existing suite covering the
  `ContainerFactory` fallback itself, and the source of the injectable-failure pattern
