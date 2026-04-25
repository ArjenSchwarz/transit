# Design: Duplicate Display ID Cleanup

## Overview

Adds a `DisplayIDMaintenanceService` that scans for tasks/milestones sharing a `permanentDisplayId`, raises the CloudKit counter fence before reassigning, then rewrites loser IDs through the existing `DisplayIDAllocator`. Three surfaces wrap the service: a Settings "Data Maintenance" view, two App Intents, and two MCP tools gated behind a new `MCPSettings.maintenanceToolsEnabled` toggle.

## Architecture

### New code

| Path | Purpose |
|---|---|
| `Services/DisplayIDMaintenanceService.swift` | Orchestrator: scan, counter-advance, reassign, single-flight guard |
| `Services/DisplayIDMaintenanceTypes.swift` | `DuplicateReport`, `ReassignmentResult`, `FailureCode` enum, JSON encoders |
| `Views/Settings/DataMaintenanceView.swift` | Two-step UI: scan → report → confirm → reassign → result |
| `Intents/ScanDuplicateDisplayIDsIntent.swift` | Read-only intent returning `DuplicateReport` JSON |
| `Intents/ReassignDuplicateDisplayIDsIntent.swift` | Mutating intent returning `ReassignmentResult` JSON |

### Modified code

| File | Change |
|---|---|
| `Services/DisplayIDAllocator.swift` | Add `CounterStore.advanceCounter(toAtLeast:retryLimit:)` with default implementation that retries on conflict |
| `MCP/MCPSettings.swift` | Add `maintenanceToolsEnabled: Bool` UserDefaults-backed, default off |
| `MCP/MCPToolDefinitions.swift` | Split `all` into `coreTools` + `maintenanceTools`; `tools(includingMaintenance:)` helper |
| `MCP/MCPToolHandler.swift` | Inject `MCPSettings` and `DisplayIDMaintenanceService`; `handleToolsList` filters by flag; `handleToolCall` rejects maintenance names when gated off, with a distinct message; dispatch handlers inline (no separate file) |
| `MCP/MCPTestHelpers.swift` | Update handler constructor to pass stub `MCPSettings` and stub maintenance service |
| `Views/Settings/SettingsView.swift` | iOS: new "Data Maintenance" section; macOS: new `.dataMaintenance` category and detail; MCP section gains a `Toggle("Expose maintenance tools")` |
| `Views/NavigationDestination.swift` | New `.dataMaintenance` case |
| `TransitApp.swift` | Construct `DisplayIDMaintenanceService` with both allocators; register with `AppDependencyManager`; pass `MCPSettings` to `MCPToolHandler` |

### Integration audit

| Existing pattern / call site | Equivalent needed? | Note |
|---|---|---|
| `DisplayIDAllocator.allocateNextID()` | Yes — reused verbatim for loser replacements | No changes |
| `DisplayIDAllocator.promoteProvisionalTasks` / `MilestoneService.promoteProvisionalMilestones` single-flight flags | Partial — maintenance service has its own `isReassigning` flag. Flags do *not* exclude each other; safety comes from advancing the counter before any reassignment allocation | See "Concurrency envelope" below |
| `CounterStore` protocol | Yes — add `advanceCounter(toAtLeast:retryLimit:)` default impl. Default composes `loadCounter` + `saveCounter` with an internal retry loop | `CloudKitCounterStore` does not override |
| `TaskService.findByDisplayID` / `MilestoneService.findByDisplayID` duplicate guards | No — maintenance service does its own fetch+group, bypassing those guards | Avoids disabling the guards |
| `CommentService.addComment(to:content:authorName:isAgent:save:)` | Yes — reused for audit trail | Called with `save: { try $0.save() }` so the comment has its own save (AC 3.4) |
| `ModelContext.safeRollback()` | Yes — reused on per-group save failure | No changes |
| `ModelContext.refresh(_:mergeChanges:)` | Yes — used for stale-ID guard so CloudKit-merged peer changes are visible | Called once per loser before reading `permanentDisplayId` |
| `AppDependencyManager.shared.add(dependency:)` in `TransitApp.init` | Yes — maintenance service registered for Intent `@Dependency` | Matches other services |
| Shared `container.mainContext` rule (T-173) | Yes — service uses `container.mainContext` | |
| `MCPSettings` `@Observable` + `didSet` | Yes — new field follows the same pattern | |
| iOS `SettingsView` Form sections / macOS `SettingsCategory` enum | Yes — new entry in each; iOS uses NavigationLink, macOS uses new enum case | MCP toggle stays in the existing `.mcpServer` category |

### Platform gating

`MCPSettings`, MCP tool definitions, and `MCPToolHandler` are already `#if os(macOS)`. The `maintenanceToolsEnabled` property is declared inside that same guard. `DisplayIDMaintenanceService`, `DataMaintenanceView`, and both App Intents are cross-platform.

### Concurrency envelope

Reassignment and promotion can run concurrently. The safety argument has two parts:

1. **Counter advance happens first in the run.** `reassignDuplicates` advances the counter to `max(sampledMax, currentCounter) + 1` *before* any loser allocation. After this point every `allocateNextID` call — from maintenance, from promotion, from `createTask`/`createMilestone` — gets a value strictly greater than any existing `permanentDisplayId`. No subsequent allocation can land in an existing duplicate group.
2. **Promotion does not touch losers.** Promotion queries `permanentDisplayId == nil`; losers have non-nil IDs. The write sets on the two passes are disjoint.

`isReassigning` is a plain `Bool` mutated only on the main actor; no `Mutex` needed. A second `reassignDuplicates` call while one is running returns `status: "busy"` and exits (AC 7.1). `scanDuplicates` is read-only and is not guarded — it can run during a reassign.

## Components and Interfaces

### DisplayIDMaintenanceService

```swift
@MainActor @Observable
final class DisplayIDMaintenanceService {
    init(
        modelContext: ModelContext,
        taskAllocator: DisplayIDAllocator,
        taskCounterStore: DisplayIDAllocator.CounterStore,
        milestoneAllocator: DisplayIDAllocator,
        milestoneCounterStore: DisplayIDAllocator.CounterStore,
        commentService: CommentService,
        clock: @escaping () -> Date = { Date.now }
    )

    func scanDuplicates() throws -> DuplicateReport
    func reassignDuplicates() async -> ReassignmentResult
}
```

Non-obvious contracts:
- `scanDuplicates` is synchronous: two `FetchDescriptor` reads, client-side group-by, winner selection.
- `reassignDuplicates` internally calls `scanDuplicates` to establish `sampledMax` and the group list — the caller does not need to pass the scan result. This keeps the single-flight guard's window around the full read-modify-write cycle.
- `reassignDuplicates` never throws; every failure is captured in `ReassignmentResult` with a `FailureCode`.
- A second concurrent call returns `ReassignmentResult(status: "busy", groups: [], counterAdvance: nil)`; the first call is unaffected.
- `clock` is injectable so tests pin the ISO-8601 date in audit comments.

`CounterStore` is surfaced on the service constructor (not only the allocator) because counter-advance needs direct access to the store, separate from per-call allocations.

### Counter store extension

```swift
extension DisplayIDAllocator.CounterStore {
    func advanceCounter(toAtLeast target: Int, retryLimit: Int = 5) async throws {
        var attempt = 0
        while attempt < retryLimit {
            attempt += 1
            let snapshot = try await loadCounter()
            if snapshot.nextDisplayID >= target { return }
            do {
                try await saveCounter(
                    nextDisplayID: target,
                    expectedChangeTag: snapshot.changeTag
                )
                return
            } catch let error as DisplayIDAllocator.Error where error == .conflict {
                continue
            }
        }
        throw DisplayIDAllocator.Error.retriesExhausted
    }
}
```

The re-read in the loop means a racing writer that already moved the counter past `target` short-circuits the advance to a no-op — the common case under concurrent allocation. `CloudKitCounterStore` does not override; in-memory test stores inherit the default.

### DisplayIDMaintenanceService.reassignDuplicates flow

1. Check `isReassigning`; if true → return busy.
2. Set `isReassigning = true`; `defer { isReassigning = false }`.
3. `let report = try scanDuplicates()`.
4. For each record type with observed duplicates, call `store.advanceCounter(toAtLeast: sampledMax + 1)`. Capture per-type `counterAdvance` entry: either `advancedTo: <final counter value>` or `warning: <error description>`. A counter-advance failure aborts reassignment for that type only; the other type still runs.
5. For each group (tasks first, then milestones, display ID ascending):
   1. For each loser, in group order:
      1. `modelContext.refresh(loser, mergeChanges: true)`.
      2. If `loser.permanentDisplayId != scannedValue` → group outcome `stale-id`, break loser loop.
      3. `let newId = try await allocator.allocateNextID()`. On throw → `allocation-failed`, break loser loop.
      4. `loser.permanentDisplayId = newId; try save(context)`. On throw → `safeRollback()`, `save-failed`, break loser loop.
      5. For tasks only: `try commentService.addComment(to: loser, content: auditText, authorName: "Transit Maintenance", isAgent: true, save: { try $0.save() })`. On throw → record `commentWarning` on this reassignment, continue.
      6. Append reassignment entry to group outcome.
6. Return `ReassignmentResult`.

Audit comment body template:

```
Display ID changed from T-<oldId> to T-<newId> during duplicate cleanup on <YYYY-MM-DD>.
```

The `T-` prefix is used even though this code path is task-only (milestones get no comment); it matches user-visible formatting. Date is formatted from the injected `clock()` via ISO-8601 date component only.

### MCPSettings addition

```swift
#if os(macOS)
extension MCPSettings {
    private static let maintenanceToolsKey = "mcpMaintenanceToolsEnabled"
    // ... property + UserDefaults init
}
#endif
```

### MCPToolHandler changes

New init signature:

```swift
init(
    taskService: TaskService,
    projectService: ProjectService,
    commentService: CommentService,
    milestoneService: MilestoneService,
    maintenanceService: DisplayIDMaintenanceService,
    settings: MCPSettings
)
```

Call sites that must change:
- `TransitApp.swift` (production wiring)
- `MCPTestHelpers.swift` (shared test factory) and any `MCPToolHandler(...)` construction inside `MCP*Tests.swift` files

`handleToolsList` uses `MCPToolDefinitions.tools(includingMaintenance: settings.maintenanceToolsEnabled)`. `handleToolCall` checks the flag once at the top of the switch; when off, a call for `scan_duplicate_display_ids` or `reassign_duplicate_display_ids` returns `methodNotFound` with message:

```
Tool 'scan_duplicate_display_ids' is disabled. Enable maintenance tools in Transit Settings.
```

The JSON-RPC error code stays `methodNotFound` (AC 5.5); the message alone differentiates a gated-off maintenance tool from an unknown tool.

### DataMaintenanceView state machine

Single `@State` enum, five cases: `.idle`, `.scanning`, `.scanned(DuplicateReport)`, `.reassigning`, `.done(ReassignmentResult)`. Confirmation is a `.alert` with `Button(role: .destructive)` (AC 4.6). Buttons disabled during `.scanning` and `.reassigning` (AC 4.3).

### JSON shapes (shared across MCP and Intent)

`DuplicateReport`:
```json
{
  "tasks": [ { "displayId": 5, "records": [<recordRef>, ...] } ],
  "milestones": [ ... ]
}
```

`recordRef`:
```json
{
  "id": "uuid",
  "name": "string",
  "projectName": "string",
  "creationDate": "ISO-8601",
  "role": "winner" | "loser"
}
```

`projectName` is the literal `"(no project)"` when the relationship is nil (AC 1.6). `role` is retained alongside winner-first ordering (AC 1.8) because consumers may re-sort for display.

`ReassignmentResult`:
```json
{
  "status": "ok" | "busy",
  "groups": [
    { "type": "task" | "milestone",
      "displayId": 5,
      "winner": { "id": "...", "name": "..." },
      "reassignments": [
        { "id": "...", "name": "...", "previousDisplayId": 5, "newDisplayId": 127,
          "commentWarning": "string or null" }
      ],
      "failure": { "code": "allocation-failed", "message": "..." } | null
    }
  ],
  "counterAdvance": {
    "task":      { "advancedTo": 128, "warning": "string or null" } | null,
    "milestone": { "advancedTo":  42, "warning": "string or null" } | null
  } | null
}
```

`counterAdvance` is always a key in the envelope; value is `null` when `status == "busy"`, a non-null object otherwise. `counterAdvance.task` / `counterAdvance.milestone` is `null` only when the run observed zero records of that type (no fence needed).

The Intent layer wraps with existing `IntentHelpers` JSON conventions. MCP wraps with the existing `content: [{type: "text", text: <json>}]` envelope.

### Winner-stale acknowledgement

AC 2.3 guards losers only. If a peer device has changed the winner's ID between scan and reassign, the group proceeds using the stale winner. This is acceptable: the worst outcome is a still-duplicated state that the next run will detect. A second guard for winners would double the refresh cost with no improvement over "re-run the tool." Captured in the Decision Log risks section.

## Error Handling

Group-level `FailureCode` (raw strings match the `failure.code` field in JSON):

| Code | When | Effect |
|---|---|---|
| `allocation-failed` | `allocateNextID()` throws | Loser loop for the group stops; next group still attempted |
| `save-failed` | `modelContext.save()` for the ID change fails | `safeRollback()` invoked; loser loop stops for the group |
| `stale-id` | Post-refresh, loser's stored `permanentDisplayId` no longer matches the scanned value | No write; group recorded as stale |

Run-level warnings (surfaced in `counterAdvance.<type>.warning` or as the `commentWarning` field on a reassignment entry):

| Code | Scope |
|---|---|
| `counter-advance-failed` | Per-type run-level, in `counterAdvance.<type>.warning`. Stops reassignment for *that* type only |
| `comment-failed` | Per-reassignment-entry warning, not a group failure. ID change persists |

Retry policy: only `advanceCounter(toAtLeast:)` and the existing `allocateNextID` loop retry. No other path retries.

## Testing Strategy

Unit tests use `TestModelContainer.newContext()` and an in-memory `CounterStore` double (already used by `DisplayIDAllocatorTests`) with injectable failure behaviour. Test suite marked `@Suite(.serialized)` per existing SwiftData convention.

### Cases per requirement

| AC | Test |
|---|---|
| 1.1 / 1.2 | Two tasks sharing ID → reported once; two milestones sharing ID → reported once |
| 1.3 | Records with `permanentDisplayId == nil` are excluded |
| 1.4 | Task T-5 and milestone M-5 → not a duplicate |
| 1.5 | Oldest `creationDate` wins; tie → smallest UUID wins |
| 1.6 | `project == nil` → `projectName == "(no project)"` |
| 1.8 | Groups ordered by ascending displayId; winner-first within group |
| 2.2 | After reassign, every new ID is greater than every pre-run `permanentDisplayId` of that type |
| 2.3 | Mutate loser's ID in a separate context before reassign runs; re-fetch then reads fresh value; run reports `stale-id` and does not write |
| 2.4 (position) | Counter is advanced *before* any loser allocation; subsequent `allocateNextID` returns values ≥ `sampledMax + 1` |
| 2.4 (CAS retry) | Inject conflict once on counter save → advance succeeds on retry. Inject permanent failure → counter-advance-failed warning for that type, loser loop does not run for that type |
| 2.5 | Zero-duplicate run still advances counter; all-groups-fail run still advances counter |
| 2.7 | Each failure path produces the exact string code |
| 3.1 / 3.2 | Reassigned task has appended Comment with `authorName == "Transit Maintenance"`, body contains `T-5`, `T-127`, and the clock-injected date |
| 3.3 | Milestone reassignments create no Comment |
| 3.4 | Comment-save failure → ID persisted, `commentWarning` populated, group not marked failed |
| 4.6 | UI test: Reassign Losers opens alert with destructive confirm button |
| 5.5 | `tools/list` with flag off excludes both tools; `tools/call` for either → methodNotFound with the "disabled" message |
| 5.6 | Toggle change via `MCPSettings` reflects immediately in next `tools/list` without restart |
| 6.3 | Same scenario via MCP and Intent → top-level keys and value types match |
| 7.1 | Overlap two `reassignDuplicates` calls; second returns `status: "busy"` with empty groups, non-null `counterAdvance` null |
| 7.2 | Interleave reassign + promotion on disjoint record sets via `Task`+`Task.yield`; post-condition: no duplicate IDs and no lost IDs. Additional test: racing allocation during counter-advance triggers the CAS retry path |
| 8.1 | Allocation failure on one group does not abort subsequent groups |
| 8.3 | Save failure restores pre-run ID on next read; group has `save-failed` |
| 8.4 | Clean data → `groups == []`; counter-advance still attempted and shows `advancedTo >= preCounter` |

### Property-based testing

Rejected. The interesting invariant is "no two same-type duplicates after any interleaving," which requires concurrency-interleaving generators rather than value generators; Swift Testing has no ergonomic story for that. The AC 7.2 tests above use explicit `Task.yield` points to exercise the two known interleaving windows (pre-allocation and between ID-save and comment-save).
