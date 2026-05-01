# Display ID Maintenance

## Overview

- `Transit/Transit/Services/DisplayIDMaintenanceService.swift` scans all tasks and milestones, groups duplicate `permanentDisplayId` values client-side, and picks the winner by oldest `creationDate` with UUID-string tiebreak.
- `reassignDuplicates()` advances each counter to at least `max(existingID) + 1` before rewriting losers, so future allocations should stay above the current fence.
- Reassigned tasks get an agent-authored audit comment through `CommentService`; milestones do not have comment support.
- The feature is exposed through Settings (`DataMaintenanceView`), two App Intents, and two gated MCP tools.

## Current gotchas

- The stale-ID guard is intended to protect against peer devices changing a loser between scan and write. The current implementation re-fetches by UUID via `FetchDescriptor` (Decision 11) and relies on whatever local state SwiftData has merged at that point. CloudKit-merged peer changes are visible only once SwiftData has applied them locally; an in-flight remote write is not detected. See Transit bug `T-1061`.
- The single-flight test (`secondConcurrentCallReturnsBusy`) interleaves two `Task`s using `Task.yield()`, which is not a hard ordering guarantee. The test passes consistently in practice but a deterministic gate (e.g. an injected slow `CounterStore` parking on an `AsyncStream` continuation) would harden it against scheduler variance.
- The stale-ID guard branch (`loserTask.permanentDisplayId != displayId` after re-fetch) is not directly tested. `staleIdSkipsGroupWithoutWriting` mutates the loser before calling `reassignDuplicates`, so the inner re-scan finds no duplicate and the guard inside `reassignTaskLoser` never fires. Hooking the loser loop is the planned approach if this gap becomes load-bearing.
- Existing tests mostly cover task-only duplicate scenarios. The UI test seed in `Transit/Transit/UITestScenario.swift` does not currently exercise mixed task+milestone duplicate IDs.
