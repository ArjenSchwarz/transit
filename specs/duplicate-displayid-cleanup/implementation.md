# Implementation Notes: Duplicate Display ID Cleanup

## Summary

The feature delivers a maintenance tool that scans Transit for tasks/milestones sharing a `permanentDisplayId`, advances the CloudKit counter past any observed maximum, then reassigns fresh IDs to losers in each duplicate group. Three surfaces wrap the core service:

- **In-app Settings**: `DataMaintenanceView` (iOS + macOS) — scan → confirm (destructive alert) → reassign → result.
- **App Intents**: `ScanDuplicateDisplayIDsIntent`, `ReassignDuplicateDisplayIDsIntent` — return JSON strings with the same shape as MCP.
- **MCP tools** (macOS only): `scan_duplicate_display_ids`, `reassign_duplicate_display_ids`, gated behind a default-off `MCPSettings.maintenanceToolsEnabled` toggle.

## Walkthrough

### Beginner level

Two records ended up with the same human-facing label (e.g. two distinct tasks both called `T-5`). The fix:

1. Open Settings → Data Maintenance.
2. Tap **Scan**. The screen lists each group of records sharing an ID.
3. Tap **Reassign Losers**, confirm in the alert. Newer records (the "losers") get fresh IDs greater than any existing ID; the oldest record in each group keeps its original ID. Reassigned tasks get a comment in their detail view recording the change.

If you're scripting Transit, the same operations are available as Shortcuts (`ScanDuplicateDisplayIDsIntent` / `ReassignDuplicateDisplayIDsIntent`) and as MCP tools after toggling on **Expose maintenance tools** in Settings → MCP Server.

### Intermediate level

`DisplayIDMaintenanceService.scanDuplicates` runs two `FetchDescriptor` reads (tasks, milestones), groups by `permanentDisplayId` in memory, drops singletons, sorts the records in each group winner-first using `(creationDate asc, id.uuidString asc)` and emits a `DuplicateReport` of value-typed `RecordRef` values. Records with `permanentDisplayId == nil` (provisional) are excluded. Same-integer collisions across types (task `T-5` + milestone `M-5`) are not duplicates because each type uses its own counter.

`reassignDuplicates` is `@MainActor` and never throws. Single-flight is guarded by an `isReassigning` Bool; a re-entrant call returns `.busy` immediately. The flow:

1. Fetch tasks + milestones once. A fetch failure short-circuits to a result envelope with a counter-advance warning on both types (no silent no-op).
2. Reuse the same arrays to compute the per-type sampled max.
3. Per type, call `CounterStore.advanceCounter(toAtLeast: sampledMax + 1)` (CAS-with-retry). A counter-advance failure aborts that type only — the other type still runs.
4. Iterate groups (tasks first, ascending displayId). For each loser:
   - Re-fetch the loser by UUID and check `permanentDisplayId == scanned value` (stale-ID guard, AC 2.3 / Decision 11).
   - `allocateNextID()` via the existing `DisplayIDAllocator` (per-loser CloudKit round-trip).
   - Save the new ID. On `save()` failure, `safeRollback()` and record `save-failed`.
   - For tasks only, append a `Comment` ("Transit Maintenance" / `isAgent=true` / body containing `T-<old>`, `T-<new>`, ISO date) via `CommentService.addComment(save:)` as a separate save. A comment-save failure becomes a `commentWarning` on the entry — the ID change persists.

The `CounterStore.advanceCounter(toAtLeast:retryLimit:)` extension (default impl on the `CounterStore` protocol) is what makes step 3 race-free: load → if already past target, return; else save with the loaded `expectedChangeTag`; on conflict, retry. A racing writer that already moved the counter past target short-circuits the next iteration.

### Expert level

The counter-advance-first ordering (Decision 10) is the load-bearing safety property. After the fence is set, every `allocateNextID()` — whether from this run, from `promoteProvisionalTasks`, or from `createTask`/`createMilestone` — returns a value strictly greater than any existing `permanentDisplayId`. Promotion writes only `permanentDisplayId == nil` rows, so its write set is disjoint from losers (which have non-nil IDs). Mutual exclusion with promotion's single-flight flag is therefore unnecessary; the fence alone closes the duplicate-introduction window.

Concurrency boundaries:

- The service is `@MainActor`. `isReassigning` is a plain Bool because the only mutation site is the main actor; the await on `allocateNextID()` and `advanceCounter` suspends but cannot interleave with another reassign call (the `guard … else { return .busy }` runs before the first `await`).
- `RecordRef` is a `Sendable` value type; nothing crosses the scan/reassign boundary as a `@Model` reference. This is why the stale-ID guard uses `FetchDescriptor` keyed on UUID rather than `ModelContext.refresh(_:mergeChanges:)` (Decision 11): there is no live `@Model` to refresh.
- `DisplayIDAllocator.counterStore` is exposed (one-line accessor) so the maintenance service can call `advanceCounter` on the same store the allocator uses for `allocateNextID`. Without this exposure the service would need a parallel store reference and risk drifting from the allocator's reads.

JSON envelope shape (shared MCP + Intents):

- `DuplicateReport`: `{ tasks: [{ displayId, records: [...] }], milestones: [...] }`. Each `RecordRef` carries `id`, `name`, `projectName` (`"(no project)"` when the project relationship is nil — AC 1.6), `creationDate` (ISO-8601 date-only via `[.withFullDate]`), and `role` (`winner` | `loser`).
- `ReassignmentResult`: `{ status, groups, counterAdvance }`. `status` is `ok` or `busy`; `counterAdvance` is always present (nullable: `null` for `busy`, `{ task, milestone }` otherwise; `task`/`milestone` is `null` when no records of that type exist).
- `FailureCode` raw values: `allocation-failed`, `save-failed`, `stale-id`, `comment-failed`, `counter-advance-failed`. Group-level failures populate `group.failure`; per-type counter advance failures land in `counterAdvance.<type>.warning`; comment failures become per-entry `commentWarning` and never escalate to a group failure.

The MCP gate is two-layered: `MCPToolDefinitions.maintenanceToolNames` (derived from `maintenanceTools.map(\.name)`) is the single source of truth; `MCPToolHandler` references it for both `tools/list` filtering and `tools/call` rejection. When the toggle is off, a call returns `methodNotFound` with a distinct "is disabled" message so callers can tell a gated tool from an unknown tool. The toggle is `@Observable` + UserDefaults-backed and applies without restart.

## Completeness Assessment

### Fully implemented

All 8 requirement groups (1.1 through 8.4) are implemented. Specific points worth flagging:

- **Best-effort per-group**: per-loser break inside each group; the outer for loop over groups continues regardless. AC 2.6 / 8.1 verified by the new `allocationFailureOnOneGroupDoesNotAbortNextGroup` test.
- **Counter-advance-first**: verified by `counterAdvancedBeforeLoserAllocation` (allocations return `>= sampledMax + 1`).
- **CAS retry on counter advance**: covered by `CounterStoreAdvanceTests.retriesAndSucceedsOnTransientConflict` and the `shortCircuitsWhenRacingWriterAdvancedPastTarget` test.
- **Audit comment template**: `Display ID changed from T-<old> to T-<new> during duplicate cleanup on <YYYY-MM-DD>.` — author "Transit Maintenance", `isAgent=true`, asserted in `happyPathTaskReassignment`.
- **Two-save audit (Decision 7)**: ID save first, comment save second; comment failure becomes `commentWarning`, not group failure.
- **Single-flight (AC 7.1)**: `secondConcurrentCallReturnsBusy` exercises the overlap and asserts `status == .busy` + empty groups + nil `counterAdvance` for the second call.

### Partially tested

- **AC 3.4 (`comment-failed`)**: code path exists (`appendAuditComment` returns the warning) but no test injects a `CommentService.addComment` failure. Adding a stub would require turning `CommentService` into a protocol or accepting a closure for the comment-save step. Documented as a follow-up rather than a blocker because the path is small (5 lines) and structurally identical to the unit-tested counter-advance failure path.
- **AC 8.3 (`save-failed`)**: code path uses `safeRollback`; `loserTask.permanentDisplayId` is mutated then save() throws — rollback puts the in-memory object back to its pre-mutation state. No test injects a `ModelContext.save()` failure mid-loop because the in-memory `ModelContext` does not expose a save-failure injection seam. Same follow-up class as AC 3.4.
- **AC 7.2 interleave reassign + promotion**: the design's testing strategy lists this with `Task.yield`. Not present. The counter-advance-first ordering makes the worst case bounded (no duplicates can be introduced post-advance), but a direct test would harden the invariant.

### Documented divergence from design

- **Stale-ID guard mechanism**: design and Decision 6 reference `ModelContext.refresh(_:mergeChanges:)`; the implementation uses `FetchDescriptor<Type>(predicate: #Predicate { $0.id == id })`. Both paths surface the same committed local state because `RecordRef` (not `@Model`) crosses the scan/reassign boundary. Captured in **Decision 11** of the decision log.

## Files

| Layer | File |
|---|---|
| Core service | `Transit/Transit/Services/DisplayIDMaintenanceService.swift` |
| Value types | `Transit/Transit/Services/DisplayIDMaintenanceTypes.swift` |
| Counter advance | `Transit/Transit/Services/DisplayIDAllocator.swift` (extension) |
| Settings UI | `Transit/Transit/Views/Settings/DataMaintenanceView.swift` |
| iOS/macOS Settings wiring | `Transit/Transit/Views/Settings/SettingsView.swift`, `SettingsCategory.swift` |
| Navigation | `Transit/Transit/Models/NavigationDestination.swift` |
| App Intents | `Transit/Transit/Intents/ScanDuplicateDisplayIDsIntent.swift`, `ReassignDuplicateDisplayIDsIntent.swift` |
| MCP tools | `Transit/Transit/MCP/MCPToolDefinitions.swift`, `MCPToolHandler.swift`, `MCPSettings.swift` |
| App-level wiring | `Transit/Transit/TransitApp.swift` |
