# Bounded read freshness — design

Review status: approved unchanged by the user in the parent conversation (Sentinel_541ceb19e7c8819193d04d23c5263041), including final scope/publication amendments at 5639c40. Tasks and implementation are also approved (Sentinel_c2e9343628948191b921868234aaf409).

Current transport decision: the approved latest-only T2383 adapter accepts one JSON-RPC object per POST and rejects arrays. Wire-batch and mixed-delivery passages below preserve the historical foundation design and generic aggregation evidence only. Final routing must use the modern adapter; no dual-era production path is required. Identifier batches inside `query_tasks` and application batches such as `mutate_tasks` remain distinct from wire arrays.

## Architecture

Place deadline/admission coordination between decoded Hummingbird requests and MainActor read dispatch. Store access remains MainActor isolated; encoded bytes, immutable captures, freshness evidence, and retention are safe to handle outside it. A caller timeout ends response delivery, not the physical operation's admission lifetime.

### Deadline and publication

`MCPReadCoordinator` is process-lifetime, nonisolated, Sendable, lock-protected state. It reserves at most eight physical workers in decoded element order before hopping to MainActor. A JSON-RPC batch has one admission instant; an identifier batch inside `query_tasks` consumes one worker. Read notifications consume physical capacity but emit no response. Invalid protocol elements retain existing validation behavior; a classified covered read gets the deadline even if its tool arguments are invalid.

Record the absolute admission instant and cutoff before fallback preparation; preparation is inside the budget and never resets the clock. At admission, pre-encode the request-specific timeout/busy tool result without store access. Start a strict DispatchSourceTimer on a userInitiated concurrent queue with zero leeway at admission +4,850 ms, reserving the remaining 150 ms of the 5,000 ms contract for compact response completion. Use explicit `@concurrent` async transport helpers; the timer completes the continuation directly. Do not create a task inheriting MainActor from the timer or use a task group whose exit waits for the canceled physical worker.

Run the physical worker as an unstructured task with one admitted operation ID. It checks the terminal/generation token before starting store work and between bounded stages. The route awaits the single-winner response gate, not the worker. The worker's finalizer alone releases its physical permit. Timeout, canceled clients, stopped service, and restarted service never reset unfinished counts. Service generations close admission and invalidate unpublished work; the same coordinator survives stop/start within the process.

Success requires final JSON-RPC bytes ready before the internal cutoff. Prepare cursor/snapshot publications privately, including capacity reservations, before offering success. A short synchronized commit chooses success and transfers prepared immutable retention entries together; if timeout or generation change wins, cancel reservations and discard the staged data. The synchronized commit performs no fetch, filesystem operation, encoding, await, or MainActor hop. Existing retained task-query limits remain eight snapshots, 16 MiB, and 300 seconds; temporary worker captures remain subject to physical admission and deadline, not a promised total-byte bound.

For read-only JSON-RPC batches, pre-encode a complete valid fallback array at decoded admission, preserving known invalid/busy entries and giving each admitted read its timeout result; omit notifications. Keep that Data ready in an independent batch terminal gate before dispatch. Assemble candidate success bytes privately outside MainActor. The strict timer can select the already complete fallback without waiting for/canceling an in-progress large array copy. Only a complete candidate selected before cutoff can atomically commit its prepared publications. If final assembly misses cutoff, no candidate success/retention is exposed. All-notification batches retain HTTP 202.

An admitted element permit stays held until its physical capture/transformation/encoding finishes. Batch assembly additionally retains one participating element's permit until assembly physically finishes; its capture/encoding must have finished before assembly starts, so the same permit never covers concurrent workers. Other completed element permits can release. At cutoff, lingering assembly remains counted even though the fallback was returned. Batches with no admitted elements return their prebuilt invalid/busy bytes without launching assembly. Timer/short terminal commits do not launch uncounted long work.

Mixed batches preserve write order and behavior; covered reads keep the common admission deadline and pre-encoded per-read errors, while combined delivery may await writes. When a preceding write occupies MainActor beyond the read cutoff, select its following read's timeout without dispatching a store fetch. Do not commit a covered result's retention unless its encoded bytes won that read's terminal gate; mixed delivery does not authorize late capture/publication.

### Coherent capture

`MCPReadCaptureBuilder.capture` runs synchronously in one nonawaiting MainActor scope. Use a new `ModelContext(container)` with autosave disabled for saved data; never transact, save, or roll back `container.mainContext`. Shared UI/MCP write services keep their contexts. A saved write is visible to the fresh capture, while uncommitted UI edits are not promoted into saved-state evidence.

Fence a persisted capture with the latest `DefaultHistoryTransaction` token/storeIdentifier, read with `HistoryDescriptor` sorted by descending transactionIdentifier and fetchLimit 1. Read the initial watermark through a fresh context, create the capture context after that watermark, copy all selected data/relationships, then read the final watermark through another fresh context. Require equal valid watermarks plus a stable import-monitor generation. Detect changed/expired/unavailable history or incomparable store scope as `incoherent_capture`; return no partial view and perform no unbounded retry. An empty persisted store uses an explicit empty-history sentinel, validated again after capture. The container has one configured domain store; foreign store history is rejected. In-memory CloudKit-free fixtures use a nonawaiting actor-only fence with no external writers, explicitly injected in tests.

Resolve project selectors inside the fenced capture and freeze their physical project identity; do not resolve a selector against a separate pre-capture store view. Copy relationship physical identifiers while models are live on MainActor. Every selected property and revision is frozen before leaving that scope. No live `@Model`, `ModelContext`, `[String: Any]`, or unchecked model wrapper crosses the actor boundary. Filtering, aggregation, projection, and output serialization operate on DTOs. History/import evidence is internal and does not replace the opaque public snapshot ID.

### Freshness

`MCPImportEvidenceMonitor` subscribes to `NSPersistentCloudKitContainer.eventChangedNotification` before the server admits reads. Its callback copies type, event identifier, store identifier, start/end dates, success and failure category into Sendable values; process them on a non-MainActor serialized queue. Ignore setup/export events and unrelated stores; every relevant transition advances a generation fence. Retain the last relevant completed successful import separately from in-flight/failed outcomes.

Associate the running SwiftData store with import events only when its public history storeIdentifier and the event's storeIdentifier can be positively matched. Fresh-context capture, equal history fencing, and import generation fencing must establish that the completed import is applicable to the chosen view. If matching or visible-history evidence is unavailable, emit `unknown`, nullable lastImportedAt, and evidence `none`; never infer a match from arrival time, bundle name, heartbeat, or a local save. The monitor records unsuccessful events without replacing the last successful import. Active mode comes from launch-fixed `SyncManager.isCloudSyncActive`.

Use no synthetic writes, app focusing, App Nap setting changes, private context access, or guessed force-pull API. The refresh trigger adapter is explicitly unavailable for the current SwiftData API. `refresh_if_needed` skips waiting for a positively applicable recent import; otherwise observes an already relevant in-flight import for at most two seconds within the remaining budget. With neither trigger nor relevant in-flight import, return local capture with `unavailable` immediately. Apply requirement 3.6's success/failure/timeout precedence. Inactive sync always skips waiting with `not_requested`/`not_applicable`/null import time. Capture-time evidence stays immutable even when newer events occur.

## Components and shared interfaces

New common code belongs in `Transit/Transit/MCP/Reads/`, macOS gated. All boundary data types are explicitly `nonisolated`, Codable as required, and Sendable; control state uses bounded locks and strict timer queues.

```swift
enum ReadCaptureScope: Sendable {
    case wholePortfolio
    case projects([LocalRecordKey]) // canonical unique physical-key set; closure is separate
    case selectedQuery // ordinary narrow read, not a reusable portfolio
}
enum CaptureCompleteness: Sendable {
    case selectedRead
    case completePortfolio // complete resolved portfolio/project scope and required identity/comment closure
}
struct CapturedReadView: Sendable {
    let completeness: CaptureCompleteness
    let captureScope: ReadCaptureScope
    let metadata: ReadCaptureMetadata
    let createdAt: ContinuousClock.Instant
    let retentionDeadline: ContinuousClock.Instant
    let projects: [ReadProject]
    let tasks: [ReadTask]
    let milestones: [ReadMilestone]
    let comments: [ReadCommentEvidence]
}
struct ReadTask: Sendable {
    let physicalKey: LocalRecordKey // encoded persistentModelID; opaque, local only
    let id: UUID
    let projectKey, milestoneKey: LocalRecordKey?
    let storedProjectID, storedMilestoneID: UUID?
    let rawStatus, effectiveStatus: String
    let creationDate, lastStatusChangeDate: Date
    let completionDate: Date?
    let revision: String? // authoritative stored-content r1 when full capture is selected
    let fullRecordWithoutCommentsJSON: Data?
    let requestedCommentRecordsJSON: Data?
}
protocol MCPRetainedViewSource: Sendable {
    func view(for snapshotID: String, now: ContinuousClock.Instant) throws -> CapturedReadView
}
struct MCPPublicationStoreID: Hashable, Sendable { let rawValue: UUID }
protocol MCPReadPublicationParticipant: Sendable {
    var publicationStoreID: MCPPublicationStoreID { get }
    func prepareAggregate(_ publications: [any MCPPreparedPublication],
                          in domain: MCPReadPublicationDomain) throws -> any MCPPreparedPublication
}
protocol MCPPreparedPublication: Sendable {
    var publicationStoreID: MCPPublicationStoreID { get }
    // Prepared/private capacity already reserved; all validation precedes every commit.
    func validateLocked(in domain: MCPReadPublicationDomain) -> PublicationRejection?
    func commitLocked(in domain: MCPReadPublicationDomain)
    func discardLocked(in domain: MCPReadPublicationDomain)
}
struct PreparedReadResult: Sendable {
    let encodedResponse: Data
    let publications: [any MCPPreparedPublication]
    let publicationErrors: PreencodedPublicationErrors // busy/expiry/capacity failure bytes
}
```

`MCPReadPublicationDomain` is one common nonisolated lock domain owned by T-63 and injected into ordinary cursor and T2382 retention stores. It owns terminal/generation state and store capacity/visibility transitions; store prepare/lookup locks never nest inside a domain commit. `prepare` reserves immutable private entries and returns an idempotent prepared-publication object; its capacity counts pending reservations as well as visible entries. `finishSuccess(operationID,generation,encodedBytes,publications)` acquires the domain once, validates time/open terminal/generation and every selected publication before committing any, inserts prepared references with nonthrowing commitLocked, and selects bytes. Prepare PreencodedPublicationErrors for busy/expiry/capacity failures outside the gate. If any publication validation fails, discard all selected reservations and select matching pre-encoded error bytes (or the read-only batch fallback), never the staged success containing an unpublished ID. No child success publishes before the complete read-only batch array is selected. The batch version selects one complete encoded array and its whole publication set. Timeout/stop/disconnect discard each prepared reservation once under the same domain. No separately locked portfolio-store commit can run after response selection. Before offering read-only batch success, coalesce every selected create/append for the same store into one aggregate immutable candidate/index version outside the gate, including the combined capacity reservation, transferred atomically from child reservations with neither double-counting nor an unreserved gap; two independently prepared whole-index swaps for one store are forbidden. Shared preparation detects duplicate operation/token ownership and excludes overwritten or unselected candidates. Validate all aggregate store candidates before any commit, then swap each store index once. Create and append reservations both count pending plus published capacity. Append prepares a complete immutable index version privately; stale-version compare-and-swap fails with READ_BUSY before terminal selection, avoiding concurrent overwrite. Ordinary cursor tokens remain UUIDv4 and reusable portfolio cursors use UUIDv8 routing even after expiry; token allocation and collision checks are atomic within the publication domain. Lookup/expiry sees only committed entries through the domain. Destruction of large discarded values occurs after unlocking. The physical worker finalizer releases permits independently of publication discard.

`LocalRecordKey` is canonical encoded `PersistentIdentifier` data, stable within one local store/capture lifecycle, independent of potentially duplicated domain UUIDs. Project/milestone DTOs carry physical key, UUID, name, raw/effective status where relevant, creation/status/completion timestamps, actual relationship physical keys, and their frozen selected wire record bytes. Comment evidence carries physical key, UUID, actual task physical key, stored task UUID, and creation timestamp. T2382 derives identity attribution from physical relationships and leaves unresolved UUID references explicit. CapturedReadView explicitly carries typed ReadCaptureScope: wholePortfolio, projects with resolved physical project keys, or selectedQuery for ordinary narrow reads. CompletePortfolio means complete declared scope plus required identity closure; it never labels a scoped capture as wholePortfolio. Closure records outside declared project keys support attribution only and cannot enlarge selected totals. T2382 retains the same typed scope in its wrapper and rejects reusable queries outside it with SNAPSHOT_INCOMPATIBLE, prohibiting later scope expansion; completeness covers every selected task and required identity/relationship/comment closure for that scope. Its aggregator/retention entry point accepts only completePortfolio captures after validating each task's required canonical revision/full record and complete comment evidence; an inadequate capture is incoherent_capture before counting or publishing, never an empty/partial success. Revision/fullRecordWithoutCommentsJSON and complete commentKeys/evidence are mandatory for completePortfolio. requestedCommentRecordsJSON represents output bodies and can be nil when includeComments is false; omission never weakens canonical revision or complete comment evidence.

The full task capture invokes T2380's authoritative `MCPRecordSnapshot.task` on all comment-covered content before comment fields are removed from output. Preserve that r1 verbatim through summary projection and snapshot queries; effective status normalization never remints revision. Summary-only ordinary task reads preserve T2380's no-comment-fetch path when comments are not requested. Portfolio capture requests the richer full/revision evidence because its reusable task view depends on it. Required comment capture failures are storage failures, never partial totals. T2382 owns its summary aggregation, projection, completion windows, reusable lifetime/capacity policy, and frozen query API; it consumes `CapturedReadView` and the same terminal publication gate.

### Wire metadata

Add optional `_meta` to `MCPToolResult`, using the key `me.nore.ig.transit/read`. Existing `content[0].text` values keep their current array/envelope shape. MCP 2025-03-26's base Result explicitly allows extension metadata; no protocol-version change is needed.

```json
{
  "_meta": {
    "me.nore.ig.transit/read": {
      "asOf": "2026-10-03T15:00:00.000Z",
      "snapshotId": "opaque-view-id",
      "freshness": {
        "syncState": "active", "assessment": "unknown",
        "assessedAt": "2026-10-03T15:00:00.000Z",
        "lastImportedAt": null, "evidence": "none",
        "recentImportThresholdMs": 30000
      },
      "read": {"policy": "refresh_if_needed", "refreshOutcome": "unavailable", "budgetMs": 5000}
    }
  }
}
```

Dates use UTC ISO 8601 milliseconds. Recency/deadlines use monotonic elapsed time to avoid wall-clock adjustment falsely improving freshness; inconsistent event clocks yield unknown. `assessedAt` equals asOf. Cursor pages retain the original complete metadata bytes and data; continuation request diagnostics use a separate request correlation ID in server logs. Snapshot expiry is a retention deadline, not the response deadline. Reused T2382 views retain exactly the same identity/evidence. Failure before a complete capture omits asOf/snapshotId and reports request/error metadata only.

## Integration and parity audit

| Existing/new site | Owner | Needs equivalent | Integration |
| --- | --- | --- | --- |
| MCPServer.makeRouter POST single route | T-63 | yes | Classify covered read before MainActor; coordinator returns encoded response bytes. Writes retain handler dispatch. |
| MCPServer.batchResponse | T-63 | yes | Common admission instant, physical element slots, read-only batch commit gate, mixed write order preserved. |
| MCPServer start/stop/tearDown | T-63 | yes | Close generation admission, invalidate unpublished work, keep process-lifetime unfinished accounting. |
| MCPToolHandler init/handleToolCall/readOnlyToolNames | T-63 | yes | Inject capture/evidence/retained sources; recognize new portfolio read; maintain fallback write protection. |
| query_tasks ordinary selectors and cursor | T-63 | yes | DTO projection, original validation precedence, frozen metadata retention; preserve T2380 revision/comment behavior. |
| query_milestones and get_projects | T-63 | yes | Selected DTO capture, outer metadata, existing filters/order/data shape. |
| scan_duplicate_display_ids/maintenance mutations | T-63 | no | Outside approved freshness scope; existing maintenance behavior remains. |
| MCPToolDefinitions common wiring/existing schemas | T-63 | yes | Optional readPolicy enum, cursor policy rules, include T2382 descriptor provider. |
| MCPTypes/MCPToolResult | T-63 | yes | Typed optional _meta and common DTO/error value types. |
| TransitApp service construction | T-63 | yes | One process-lifetime read coordinator and launch-fixed mode monitor; container supplied only to capture builder. |
| MCPToolHandler+PortfolioSummary/+SnapshotTaskQuery | T2382 | yes | New separate modules consume shared DTO/source; query_tasks snapshotId dispatch wired by T-63. |
| MCPPortfolioToolDefinitions/snapshot store | T2382 | yes | Supplies descriptor and retained source/transaction hooks; no concurrent edits to shared files. |
| Write coordinator/receipt/revision implementation | T2380 | no | Depend on current authoritative snapshot routine; no duplicate write safeguards or receipt schema deployment. |
| App Intent reads/UI services | — | no | Outside covered MCP transport contract. |

T2382 submits interfaces/helper files before shared-file wiring. PR249 merged as 201205bd4e786c7f152d8f99006b37da7da888c7; its tree equals inspected head b618acf9e3d66a4a1ce493eea94091c058721731. Parent coordinates foundation alignment before implementation; do not alter the T2380 working branch. T2382 proposes a separate eight-view/16 MiB encoded retention budget alongside ordinary eight/16 MiB retention, subject to this design approval. The 32 MiB combined logical encoded ceiling is not a bound on heap use or temporary admitted captures. The new MCPWriteReceipt production schema remains an owner release prerequisite.

## Errors and diagnostics

Keep protocol validation/unknown-method errors unchanged. Covered execution failures use tool results with isError true. Task-query errors retain their existing codes; additional category is metadata. For project/milestone execution errors use READ_FAILED with category `storage_failure`, `serialization_failure`, or `incoherent_capture`. `READ_TIMEOUT` and `READ_BUSY` have no successful capture metadata. Cursor/input/capacity errors retain existing precedence. Timeout wins once selected; late failures are diagnostics only.

Log request correlation, tool, generation, monotonic admission/deadline, outcome, and measured queue/refresh/capture/transform/serialize/batch durations. The worker finalizer logs correlated late completion/discard and retained physical count. Timer response uses precomputed small bytes and a bounded diagnostic enqueue; logging cannot perform synchronous filesystem work on the timer or keep a response gate locked. Document backoff after busy/timeout, cursor replay until expiry, and mixed-batch delivery limitations.

## Risks and assumptions

- Risk: SwiftData/CloudKit may not expose matching store identifiers or import-visible history in unfocused signed execution | Verify: early live import/history correlation probe on the configured store | If wrong: unknown freshness/null import time and unavailable refresh; never assert recency.
- Risk: persistent history may not fully fence a concurrent CloudKit commit or may be unavailable/purged for a supported store | Verify: early saved local/cross-context/live-import and empty-versus-purged history probes | If wrong: incoherent_capture failure for that store; bring any alternative capture mechanism back for design approval before depending on it.
- Risk: end-to-end scheduling/encoding at production volume exceeds internal headroom | Verify: transport load and blocked-MainActor/batch probes before implementation completion | If wrong: return pre-encoded timeout earlier within the approved budget; retain physical accounting and defer success.

## Testing strategy and traceability

The isolated Xcode27/Swift6.4 prototypes under this spec establish timer independence, retained physical permits, late-publication suppression, and basic fresh-context/history fencing. They are not production integration tests. Use Swift Testing and the repository's owning TestModelContainer fixtures for app tests; serialize SwiftData suites. Coordinate simulator/full build gates with the parent.

| Requirements | Design/test evidence |
| --- | --- |
| 1.1–1.6 | Strict coordinator one-shot race, physical cap/stop-restart, pre-encoded errors, shared batch admission/aggregation; test blocked MainActor, slow encoding, canceled request, eight lingering/ninth busy, invalid/both notification modes, and late completion. |
| 2.1–2.6 | DTO capture/history/import fences, physical relationship attribution, `_meta`; test saved multi-entity changes, empty/scoped views, unknown/unrelated/failed events, wrong store, date inconsistency, and asOf/assessedAt equality. |
| 3.1–3.6 | Optional readPolicy parser + evidence observation; test cached/default/inactive, recent import, in-flight success/failure/timeout, no trigger, zero wait, and input precedence. |
| 4.1–4.4 | Error categories/unchanged writes; test fetch/comment/history/serialization failures, legitimate empty result, existing identifier outcomes, and T2380 input/output/revision parity. |
| 5.1–5.4 | Encoded retention + shared view identity; test import/edit between pages, byte-identical metadata replay, cursor policies/expiry, and T2382 same-view query projection without r1 reminting. |
| 6.1–6.3 | Caller guide and diagnostic correlation; validate phase durations/late discard, mixed delivery documentation, backoff examples, and no timer-path logging delay. |

Use seeded generated event sequences in Swift Testing for terminal race/permit invariants and cursor replay: one response per ID, no publication after terminal timeout, unfinished count never above eight or below zero, and immutable metadata across randomized import/local-edit sequences. No external property-testing dependency is required.

Research informing the design: [MCP Result metadata schema](https://raw.githubusercontent.com/modelcontextprotocol/specification/main/schema/2025-03-26/schema.ts), [Apple ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext), [Apple history fetching](https://developer.apple.com/documentation/swiftdata/fetching-and-filtering-time-based-model-changes), [Apple CloudKit events](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/event), and [Swift SE-0461 executor isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md). Installed Xcode27 SDK interfaces confirm history sorting/fetchLimit and event properties for the target platform.
