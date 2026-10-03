# Design: MCP Write Safety

Ticket: T-2380 | Requirements: approved | Design: approved on 2026-10-03

## Overview

Protect the eight specified MCP writes with a durable receipt and a comparison against current local record state. The receipt's completed result and the domain mutation share one SwiftData save; replay reads the receipt without resolving or modifying the target.

## Architecture

`MCPToolHandler.handleToolCall` routes protected tools through one `MCPWriteCoordinator` owned by `TransitApp`. Existing read tools and gated maintenance tools retain their dispatch paths. The coordinator uses the existing services and `container.mainContext`; no view-provided model crosses into another writable context. The save boundary follows [Apple's description of SwiftData transactions](https://developer.apple.com/videos/play/wwdc2024/10075/); crash durability is an early verification gate below.

Add `MCPWriteReceipt` to the existing single-store schema on all platforms. Receipts sync with that store but are identified by `(localScopeID, tool, key)`. A local sidecar beside the configured store contains the scope UUID, created atomically on first use and retained across launches and sync preference changes. Failure to read or persist this identity disables protected writes; it never falls back to a session UUID. Reinstall, store replacement, or removal of local identity is outside the same-local-store guarantee. Test fixtures inject scope identity.

The local sidecar directory also holds reservation guards: scope/tool/key, canonical payload and format version, receipt UUID, and optional terminal expiry. Persist each guard before accepting its key using atomic file replacement and durability checks. Guards retain payload binding when a receipt cannot be read or is missing; they contain no domain result and do not participate in committing a domain effect. A guard without a valid receipt blocks that key as uncertain, including after restart. Unreadable or inconsistent guard storage disables new protected writes for the scope rather than regenerating it. Retain guards through terminal replay expiry; unresolved guards never expire.

A store-scoped advisory file lock is held for the lifetime of an active MCP write coordinator. A second process using the same store cannot enable protected writes while another holds it; failure returns `STORE_BUSY`. Within the process, an active-request map reserves each key before any suspension. All synchronous mutation sections execute on MainActor. No database uniqueness constraint or cross-device exclusion is assumed.

### Write sequence

1. Validate the arguments envelope, tool's allowed fields, key, revision syntax, and scalar input types. Reject unknown fields and malformed requests without reserving a key. Perform persistence-availability and store-lock checks.
2. Canonicalize arguments, then inspect the active map, durable local guards, and receipts after eligible expiry cleanup. Compare payloads before replay: mismatch returns `IDEMPOTENCY_KEY_REUSED`; matching active work returns `OPERATION_IN_PROGRESS`; matching completed work returns its stored result. No target lookup occurs on replay.
3. For a new key, establish a saved baseline of any existing main-context changes using `context.save()` before inserting the receipt. Failure leaves those changes intact and rejects before acceptance. Persist its local guard; the key is accepted once its payload binding is confirmed durable. Insert an `accepted` receipt and save it before asynchronous preparation. No domain command runs until this receipt is confirmed durable. A thrown guard/reservation save requires durable inspection before declaring rejection or allowing key reuse: it does not prove that acceptance failed. If no domain command has run, a live operation can prove no domain effect and persist a terminal rejection; inability to persist/read that outcome returns uncertainty with the guard intact.
4. Resolve identifiers and validate domain constraints. Task/milestone creation allocates a display ID without inserting a model. Its prepared command pins resolved reference UUIDs and normalized inputs. Allocation may consume a counter value even when the request is later rejected; counter gaps are not a domain effect.
5. After preparation, establish another saved baseline before touching domain models. If that save fails, leave existing edits intact and return an unresolved outcome for the accepted key. Otherwise re-resolve pinned UUIDs, validate references/uniqueness again, and check `expectedRevision` against a freshly captured local snapshot. There is no suspension from this check through the final save.
6. Apply the command without internal saves, build the normalized saved-record snapshot and revision, and encode the complete response. Set the receipt to `committed` with that response, completion time, and expiry. Save the domain changes and receipt together. Even a domain no-op completes its receipt while keeping the entity revision unchanged.
7. Record the terminal receipt's expiry on its guard, then return the persisted response. Failure to update the guard cannot undo a completed domain/result save: preserve the guard without expiry, replay the terminal receipt, and retry that metadata update later using the original deadline. Clear the active map only after completion or classification as unresolved; caller disconnect or notification response suppression does not discard a reserved key.

Only steps before domain mutation may suspend. Disable autosave for the synchronous mutation/serialization/save section and restore its prior setting afterward. Establishing the saved baseline is consistent with existing shared-context save behavior: it may persist pending changes from other local work, but rejection-with-no-effect refers to the requested MCP mutation. No baseline save failure invokes context-wide rollback.

### Rejections and recovery

Conclusive validation, lookup, revision, and cancellation failures after acceptance are saved as `rejected` receipts with a seven-day expiry. Preserve the exact rejected result, including the conflict snapshot. A corrected request uses a new key. If persisting that rejection fails, keep the accepted key unresolved and return `OUTCOME_UNCERTAIN` until storage is readable.

For mutation/serialization/save failure, remove newly inserted domain models before `safeRollback()`, which also refaults receipts. This happens only after a saved baseline, with no intervening suspension, so rollback cannot discard unrelated pending edits. Inspect the receipt through a fresh read-only context retaining its container:

| Durable receipt | Classification and action |
|---|---|
| Valid completed result | Return its stored committed/rejected outcome. |
| `accepted`, no active operation | The atomic domain/result save did not complete. Persist and return `INTERRUPTED_BEFORE_COMMIT`, rejected with no domain effect; never rerun this accepted request automatically. |
| `accepted`, active operation | Return `OPERATION_IN_PROGRESS`, retry the same request. |
| Unreadable, missing after confirmed acceptance, malformed, or conflicting duplicate receipts | Return `OUTCOME_UNCERTAIN`; the durable guard retains the original binding and stops automatic writes for that key across restart. A mismatched retry still returns `IDEMPOTENCY_KEY_REUSED`. |

The same recovery table applies after restart. Recovery uses durable receipt state, not target presence: the target may have been edited or deleted after a successful write. A thrown save is not alone evidence of rejection. Where storage cannot prove an outcome, callers must reconcile by reading domain records; this feature exposes no force-retry or key-reset tool.

Expired terminal receipts and guards are removed lazily before key lookup and during launch cleanup. First confirm the terminal receipt and record its original expiry in the guard; after that deadline either cleanup order is safe, because a remaining guard proves the protected window ended. A guard lacking terminal expiry prevents removal of its receipt until that metadata is repaired. Never remove accepted/unresolved receipts or guards under age-based cleanup. Only the originating scope cleans its receipts; imported receipts from other scopes never authorize replay, reserve a local key, or affect a local revision. Conflicting duplicates within the same scope fail closed rather than selecting a winner.

## Components and Interfaces

New code lives under `MCP/Writes/`, except the cross-platform receipt model in `Models/`.

| Component | Contract |
|---|---|
| `MCPWriteCoordinator.execute(tool:arguments:) async -> MCPToolResult` | Owns acceptance, active keys, preparation, commit, rejection persistence, and recovery. Inject clock, identity, lock, and save/read fault seams. |
| `MCPWriteCommand` / `PreparedMCPWrite` | Typed domain command; asynchronous preparation allocates IDs only. Synchronous application validates live references and returns immutable result snapshots, tracking inserted models for cleanup. |
| `MCPWriteReceiptStore` | Scoped fetch, terminal cleanup, duplicate detection, recovery reads, and same-context receipt staging. It never independently saves a domain mutation. |
| `MCPLocalReservationStore` | Local scope identity, durable payload guards, process lock, guard expiry repair, and fail-closed startup/lookup. Guard comparison occurs before receipt recovery; absent guard for an existing receipt blocks new execution until the binding is reconstructed durably from that receipt. |
| `MCPRecordSnapshot` / `MCPRecordRevision` | One captured set of fields produces both MCP record JSON and its revision. Throw on incomplete comment fetch; do not issue a token for incomplete state. |
| `MCPCanonicalJSON` | Deterministic, typed encoding used for request identity and revision hashing; no lossy timestamp formatting or implicit Boolean/number bridging. |
| `MCPWriteOutcome` | Codable terminal/transient envelope encoded into MCP text content and retained exactly for terminal replay. |

Expose narrowly scoped service APIs to prepare and apply task/milestone creation, plus deferred-save variants of project creation and milestone deletion. Existing public CRUD defaults keep their current save behavior. The coordinator owns the context via dependency injection; external callers do not access private service contexts.

### Integration and parity audit

| Existing sites/pattern | Equivalent needed | Change |
|---|---|---|
| `TransitApp` schema and MCP handler construction; `TestModelContainer`, `FallbackOutcomeFixture`, full-schema sync fixtures | Yes | Register receipt and inject one coordinator; keep older subset-only model tests unchanged. |
| `ModelContext+SafeRollback.refaultAllEntities` | Yes | Refault `MCPWriteReceipt` after rollback. |
| Handler create task/project/milestone and add-comment methods | Yes | Translate to prepared commands; use deferred domain persistence. |
| Handler status/update task/update milestone/delete milestone methods | Yes | Check snapshot precondition and complete receipt in the same save. |
| `taskToDict`, `milestoneToDict`, `projectMetadataDict`, `commentResponse`, `statusResponse` | Yes | MCP snapshot encoder emits full saved records and revisions, including nested full comments. Summary-only project/milestone entries remain summaries. |
| `TaskService.createTask` (UUID-project overload, AddTaskSheet, CreateTaskIntent, Visual/AddTaskIntent, MCP) | Yes for service internals; no new caller inputs outside MCP | Separate allocation from synchronous insert; existing callers retain create-and-save facade. |
| `MilestoneService.createMilestone` (CreateMilestoneIntent, MilestoneEditView, MCP) | Yes for service internals; no new caller inputs outside MCP | Same prepare/apply split; existing callers retain facade. |
| `ProjectService.createProject` (ProjectEditView, MCP); `deleteMilestone` (MilestoneListSection, DeleteMilestoneIntent, MCP) | Yes | Add deferred-save variants; current callers use saving defaults. |
| `updateStatus` (DashboardView, TaskEditMerge, UpdateStatusIntent, MCP), `setMilestone` (TaskEditMerge, TaskUpdateValidator, IntentHelpers), comment mutations | No new revision-write hooks | Snapshot-derived tokens detect changes regardless of entry point; existing deferred-save behavior serves the coordinator. |
| Shared `IntentHelpers.taskToDict`, `taskUpdateResponseDict`, `milestoneInfoDict` and their intent callers | No safety fields in App Intents | Keep shared serializers unchanged; MCP adds its snapshot projection. |
| `MCPToolDefinitions`; protected handler tests and HTTP tests | Yes | Required safety fields, structured envelopes, and read-then-write test helpers. |
| Notification dispatch and JSON-RPC batch transport | No new protocol path | Protected notifications still execute and record receipts; HTTP/JSON-RPC batching retains its current ordered, non-atomic behavior. |
| Maintenance scan/reassignment dispatch | No | Excluded from receipt protection; resulting domain changes still affect snapshot revisions. |

## Data Models

`MCPWriteReceipt` has no relationships and no unique attribute. All non-optional fields have CloudKit-compatible defaults; optional result fields default to nil.

| Field | Meaning |
|---|---|
| `id: UUID` | Receipt identity, generated before acceptance. |
| `localScopeID: String`, `tool: String`, `key: String` | Local retry namespace. |
| `formatVersion: Int` | Receipt format and canonical-request encoding version. |
| `requestJSON: String` | Canonical accepted payload, excluding key; exact comparison avoids reliance on a hash collision assumption. |
| `stateRawValue: String` | `accepted`, `committed`, or `rejected`. |
| `acceptedAt: Date` | Durable acceptance timestamp. |
| `completedAt: Date?`, `expiresAt: Date?` | Terminal retention deadline: completion + 604800 seconds. |
| `resultJSON: String?`, `resultIsError: Bool?` | Exact terminal response envelope and MCP error flag. |

There is no stored revision counter on domain models. Receipt creation/cleanup does not change their revisions. Add the model to the existing schema without renaming or changing current persisted fields. Production CloudKit schema publication must include the new entity before shipping.

### Revision encoding

Use CryptoKit SHA-256 over a versioned, typed canonical snapshot: `r1:<64 lowercase hex digits>`. This is a content equality token, not an edit-history sequence: editing A to B and back to identical A produces A's token. All comparisons use the current covered state; intermediate states not observed by the caller are not an audit log.

| Entity | Covered state |
|---|---|
| Task | All current scalar fields in `TransitTask` (including raw enum values, `metadataJSON`, timestamps, permanent display ID, and UUID); assigned project/milestone UUIDs; comments sorted by UUID, each including all comment scalar fields and task UUID. |
| Project | UUID, name, projectDescription, gitRepo, colorHex. |
| Milestone | All scalar fields in `Milestone`, plus project UUID. |
| Comment | UUID, content, authorName, isAgent, creationDate, task UUID. |

Encode dates as the exact finite `timeIntervalSinceReferenceDate` bit pattern, UUIDs in lowercase canonical form, and nil distinctly from empty values. Object fields have fixed names; collections whose order is not meaningful are sorted by UUID. Retain raw persisted scalar strings for revision coverage even where returned fields use normalized accessors. The metadata JSON string is covered as stored, so an encoding-only change to that field invalidates a token.

Task revision capture fetches comments from the child side using `CommentService.descriptor`; the same comment snapshot supplies response data. Capture, precondition comparison, mutation, response capture, and final save run without suspension. Imported sync state already visible in the context is included; edits not yet imported and later CloudKit merges remain outside the guarantee.

## Wire Contract and Error Handling

Keys match `[A-Za-z0-9._:-]{1,128}` and are case-sensitive; UUID strings are suitable keys. Expected revisions match `r1:[0-9a-f]{64}`. A request's canonical arguments preserve absent versus null fields, string contents, and array order; recursively sort object keys and compare JSON numbers by value (`1` equals `1.0`), with Booleans distinct from numbers. Omitted defaults and explicit defaults remain different payloads. The receipt version selects the canonicalizer for retained replay across app upgrades.

Protected tool results use JSON in `content[0].text`, with `isError: true` for rejected or unresolved outcomes. Keep JSON-RPC errors for invalid protocol envelopes or unknown/disabled tools. The full record body uses existing normalized MCP field names and includes `revision`. All full records from read tools use the same encoder.

```json
{
  "contractVersion": 1,
  "tool": "update_task_status",
  "idempotencyKey": "caller-generated-uuid",
  "outcome": "committed",
  "accepted": true,
  "entityId": "saved-task-uuid",
  "record": {"taskId": "saved-task-uuid", "revision": "r1:..."},
  "comment": null,
  "completedAt": "ISO-8601 timestamp with fractional seconds",
  "replayExpiresAt": "ISO-8601 timestamp with fractional seconds"
}
```

`record` is a complete saved record, not the abbreviated example. Status-plus-comment returns a full comment with UUID and revision alongside the task. Comment creation returns the full saved comment. Milestone deletion returns `deleted: true` and `recordBeforeDeletion`, including its original revision; no post-deletion milestone revision is returned.

Error results use the same envelope with `error: {code, message}`, `outcome`, `accepted`, and `retryAction`. `accepted` is true for a confirmed durable key binding, false when non-acceptance is proven, and null when unreadable reservation storage prevents determining prior acceptance. Terminal accepted rejections include completion and expiry. `REVISION_CONFLICT` additionally carries `currentRecord` with its revision; stored replay returns that original snapshot, not a later live one. Pre-acceptance errors contain the validated tool/key when available but no expiry. A key mismatch does not replace or complete its existing receipt.

| Error | Outcome / retry action |
|---|---|
| `INVALID_INPUT`, missing/ambiguous references, invalid enum/reference/name, `REVISION_CONFLICT`, `CANCELLED`, `INTERRUPTED_BEFORE_COMMIT` | `rejected` / `new_request_new_key`; receipt retained only when already accepted. |
| `IDEMPOTENCY_KEY_REUSED` | `rejected`, `accepted: false` for this mismatched payload / `new_request_new_key`; original receipt remains unchanged. |
| `STORE_BUSY`, `PERSISTENCE_UNAVAILABLE`, storage failure with non-acceptance proven | `rejected`, `accepted: false` / `retry_same_request`; key not reserved. |
| `OPERATION_IN_PROGRESS` | `in_progress`, `accepted: true` / `retry_same_request`. |
| `OUTCOME_UNCERTAIN` | `uncertain`, `accepted: true` (or null if binding storage cannot be read) / `reconcile`; never suggest retry with a fresh key. |

Assign stable codes to existing domain errors rather than embedding prose-only failures. Publish the contract in tool descriptions and `docs/mcp-write-contract.md`, including read→write→same-key replay examples, no-op behavior, expiry, content-token limitations, and T-2384's shared vocabulary. Do not add batch-specific behavior.

## Risks and Assumptions

- Risk: receipt/domain crash durability or refaulting differs on the shipped SwiftData runtime | Verify: first implementation task uses a disk-backed store, child-process termination around save, reopen, and forced save failures | If wrong: stop implementation and revise the persistence design before exposing protected writes.
- Risk: adding the synced receipt entity fails against a production-shaped existing store | Verify: migrate a copied local fixture and validate the CloudKit-compatible schema before wiring handlers | If wrong: preserve the original store and revise the additive migration plan.

## Testing Strategy

Use Swift Testing and the existing owning `TestModelContainer` fixture. Add disk-backed fixtures retaining their containers for restart/recovery tests; injection points control allocation suspension, time, cancellation, save faults, and recovery-read failure. The crash probe uses a temporary test store only.

| Requirements | Verification |
|---|---|
| 1.1–1.3 | All eight schemas and dispatch routes require keys; four require revisions; malformed/unknown inputs leave no receipt or domain effect. |
| 2.1–2.5 | Same-key replay across sessions/restart, mismatch and object reordering, concurrent requests during suspended allocation, replay after target edit/delete, and stale precondition replay precedence. |
| 3.1–3.5 | Fixed clock at expiry boundaries, no expiry extension, retained rejection, unresolved key beyond seven days, cancellation/crash before acceptance and before/after final commit. |
| 4.1–4.6 | Every covered field/relationship and each excluded relationship; UI/service/intent/maintenance edits, separately saved/imported context changes, comments, no-op revisions, unreadable comment fetch, and an intervening edit during allocation. |
| 5.1–5.5 | Normalized saved records/revisions, deletion preimage, all outcome/retry classifications, failed serialization/save/recovery read, both-or-neither status/comment, and later unrelated saves proving no ghost effects. |
| 6.1–6.2 | Contract examples checked against encoders; all preceding suites plus HTTP notification/batch regression coverage. |

Additional recovery tests cover guard persistence and failure/crash windows, a missing receipt followed by another restart with matching and mismatched retries, unreadable guard storage, terminal expiry repair/cleanup in either order, and two-process lock contention and reacquisition after process termination.

For canonicalization, use deterministic generated dictionaries and nested arrays in Swift Testing (no new testing dependency): permutation of object keys preserves identity, Boolean/number and absent/null remain distinct, and round-trip decoded payloads preserve identity. For revisions, generate covered-field mutations and comment-order permutations; tokens must change for different covered state and remain equal for identical covered state.

Run focused tests during implementation, then required `make lint` and `make test-quick`; pre-push checks remain `make test` and `make test-ui`. This design phase changes Markdown only and runs document validation, not application builds.
