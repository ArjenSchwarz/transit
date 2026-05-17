# Display ID Maintenance

## Overview

- `Transit/Transit/Services/DisplayIDMaintenanceService.swift` scans all tasks and milestones, groups duplicate `permanentDisplayId` values client-side, and picks the winner by oldest `creationDate` with UUID-string tiebreak.
- `reassignDuplicates()` advances each counter to at least `max(existingID) + 1` before rewriting losers, so future allocations should stay above the current fence.
- Reassigned tasks get an agent-authored audit comment through `CommentService`; milestones do not have comment support.
- The feature is exposed through Settings (`DataMaintenanceView`), two App Intents, and two gated MCP tools.

## Current gotchas

- The stale-ID guard protects against peer devices changing a loser between scan and write. Per Decision 12, it reads the loser's committed `permanentDisplayId` through a *transient* `ModelContext(modelContext.container)`. The transient context has no registered objects, so its fetch bypasses the main context's scan-time snapshot and reads directly from the local SQLite row — including any CloudKit-merged peer change. SwiftData has **no** public `ModelContext.refresh(_:mergeChanges:)`; that API is Core Data only. Decision 11's pure `FetchDescriptor` against the main context returned the cached registered instance and missed peer-merged updates (T-1061).
- The single-flight test (`secondConcurrentCallReturnsBusy`) interleaves two `Task`s using `Task.yield()`, which is not a hard ordering guarantee. The test passes consistently in practice but a deterministic gate (e.g. an injected slow `CounterStore` parking on an `AsyncStream` continuation) would harden it against scheduler variance.
- The stale-ID guard's positive path is now covered by `peerUpdatedLoserIsSkippedWithStaleId`, which fakes the cached-stale state by saving a value to the store and then mutating the registered instance in memory before calling `reassignDuplicates`. `staleIdSkipsGroupWithoutWriting` remains as a coverage of the "scan no longer sees the duplicate" outcome.
- Existing tests mostly cover task-only duplicate scenarios. The UI test seed in `Transit/Transit/UITestScenario.swift` does not currently exercise mixed task+milestone duplicate IDs.
