# Safe task consolidation — design

Status: **design draft awaiting approval**. Requirements and all five product choices approved at `b1d02591dd214f1d2ca6cf3f196b52b01058076a`. This document defines design only; task planning and implementation await their gates.

## Architecture

Add two covered reads (`preview_task_consolidation`, `preview_task_consolidation_undo`) and two protected group writes (`consolidate_tasks`, `undo_task_consolidation`). Reuse the existing saved-capture/publication path, ordinary retention store, shared write coordinator, typed-link graph and owned commit context. Add one same-store immutable history entity for apply/reversal events; original tasks and comments stay in place.

New pure value/planning/history code belongs in `Services/TaskConsolidation/`; MCP schemas, preview projection and write adapters in `MCP/Consolidation/`; the model in `Models/TaskConsolidationEvent.swift`; native read-only history in `Views/TaskDetail/TaskConsolidationHistorySection.swift`. Platform-neutral history and planning do not depend on macOS-only MCP types.

### Integration and pattern parity audit

| Existing site / pattern | Needs equivalent | Integration |
| --- | --- | --- |
| `MCPToolDefinitions.coreTools`, protected definitions | Yes | Advertise four strict input/output contracts; apply/undo enter `MCPWriteCommand.protectedTools`. |
| `MCPReadCoordinator`/operation/admission/entry lifecycle, `MCPReadPublicationDomain`/types and read diagnostics | Yes, shared core availability | Expose native value-result entry point across platforms; app-lifetime physical admission/deadlines/cleanup are shared with macOS MCP. Keep wire/provider adapters platform-gated. |
| `TransitApp` ownership and `MCPServer` coordinator stop/start | Yes | App owns shared lifecycle; listener start/stop cancels only listener-owned requests, retaining native admission and unfinished physical slots. |
| `MCPToolHandler` read-only allowlist, routing and covered-read admission | Yes | Both previews are read-only and use the existing read coordinator; apply/undo use the retained app coordinator. |
| `MCPBoundedReadDispatcher`, `MCPReadService+CaptureRequest`, capture/projection types | Yes | Add explicit selected-group and operation-history capture requests; retain original admission/deadline/cancellation. |
| `MCPModernProviderBinding` covered set, result schemas, recovery preflight and record positions | Yes | Declare previews covered reads; declare both writes protected; project participant records and operation identities without guessed URLs. |
| `MCPTaskQuerySnapshotStore.Index`, prepared-result builders, purge/clear/replacement paths | Yes | Add typed immutable review entries to the ordinary index; every rebuilt index preserves or retires them with its descriptor roots. |
| `MCPReadPublicationDomain` reservation/terminal-selection contract | No new protocol | Use existing reservation and publication gates, including full envelope charges; never publish a usable review on timeout/failed response preparation. |
| `MCPWriteCommand.validate/prepare/apply`, `PreparedMCPWrite`, command/commit services | Yes | Add typed group cases and a consolidation service in owned services; no single-task `findByID` first-match resolution. |
| `MCPBatchWritePolicy`, `MCPWriteCommitScope`, `MCPWriteCoordinator` | Yes, existing policy path | Consolidation adapter supplies clean owned services. Apply runs one group command; retain existing acceptance, replay, dirty-context and recovery phases. |
| `TaskLinkGraph`, `TaskLinkPlan`, `TaskLinkOwnedApply`, exact occurrence selectors | Reuse | Validate the complete combined proposed graph before effects; use exact created-occurrence selectors for undo and existing removal evidence. |
| `MCPRecordSnapshot.task`, `MCPRecordRevision`, `TaskLinkIncidence` | No r1 expansion | Keep task-fields/comments/links r1 unchanged; operation evidence has a separate `o1` token. Fresh full-read history is supplementary saved data. |
| `MCPReadCaptureBuilder.copy/watermark`, capture validation and byte accounting | Yes | Share the saved boundary helper with native capture; freeze selected events plus full operation-participant/canonical dependency closure; add the entity to empty-store proof and copied-value charges. |
| `TransitApp` schema, `TestModelContainer`, schema-owning UITest fixtures | Yes | Include the additive entity in current schemas; old-store migration fixtures retain their intentional old schema. |
| `TaskDetailView`, `TaskLinksSection`, native detail state and navigation resolver | Yes, presentation only | Add history adjacent to saved relationships using the same diagnostics, source/generation invalidation, cancellable 100-ms notification coalescing and unique saved navigation. |
| `mutate_tasks`, App Intents, summaries, display-ID maintenance, existing link cleanup | No | Retain contracts; no group-item extension, implicit redirection, history deletion or new maintenance capability. |

## Public interfaces and reviewed evidence

| Tool | Input / result contract |
| --- | --- |
| `preview_task_consolidation` | `survivorTaskId`, ordered `candidateTaskIds` (1–5), nonblank `reason`, candidate-keyed `preservation`, optional `survivorEdits`, existing `readPolicy`. Returns complete originals, plan, saved metadata, `reviewId`, `reviewRevision`, `reviewExpiresAt`; no write key. |
| `consolidate_tasks` | `reviewId`, `reviewRevision`, `preservationAcknowledged:true`, `idempotencyKey`. Selected IDs/edits come only from that immutable retained review. Returns protected committed envelope with `entityId=operationId`, actual saved changes/participant records, mappings, reason and undo assessment. |
| `preview_task_consolidation_undo` | `operationId`, existing `readPolicy`. Returns historical before/after changes, exact current reversal/evidence or explicit unavailability, plus a retained undo review reference when reversal is available. |
| `undo_task_consolidation` | `operationId`, `reviewId`, `reviewRevision`, `idempotencyKey`. Requires a matching retained reversal review. Returns a protected result referencing the original operation and reversal event; an already reversed operation returns a saved no-domain-effect assessment. |

Unknown fields and wrong JSON types fail whole-shape validation before key acceptance. UUID normalization determines distinctness; candidate order remains request identity under existing canonical JSON rules. A candidate cannot equal the survivor. Metadata is a complete replacement string dictionary when present; description is a string or explicit null; omission means unchanged. Preview shows these distinctions and applies no text trimming beyond rejecting a blank reason. Validate saved statusRawValue as a known TaskStatus and decode non-nil metadataJSON strictly as a string dictionary before planning; unknown statuses or malformed metadata make evidence unavailable rather than using accessor fallbacks. Nil metadata remains the valid empty-metadata case. Task names, priority/type, assignments and survivor status are not editable here.

Preservation contains exactly one entry per candidate, with `incorporated` source-detail/description-or-metadata field references and/or nonblank `retainedExplanation`. Entries may mix both. At least one disposition is required; references must name an actual proposed edited survivor field. The system validates accounting structure and explicit acknowledgment, not semantic equivalence or whether prose accurately captures every useful detail.

### Retained review lifecycle

Extend the existing ordinary retention index with `ConsolidationReviewEntry`: kind, local-store scope, immutable caller input, full saved original values, task r1s, canonical-path/physical-occurrence evidence, optional original operation o1, planned field/link deltas, canonical plan digest and expiry. `reviewRevision` is `p1:` plus the SHA-256 digest of the versioned canonical input/evidence/plan; it is a content comparison, not an authorization secret. The opaque `reviewId` selects the server-held entry; writes do not accept an editable client plan.

Each preview occupies one ordinary retention root for five minutes, subject to the existing eight-root/16-MiB limits. Charge retained value/index bytes and complete modern response representations before publication. Response preparation and root visibility share the existing terminal gate. Process restart or clearing ordinary snapshots invalidates reviews; apply rejects a missing/expired/wrong-kind/wrong-scope/digest-mismatched review and asks for another preview. A review is not consumed by apply and never extends its expiry.

Exact terminal replay is inspected before review lookup or current-state checks. Consequently replay still works after review expiry, later edits or restart within the original receipt window. An accepted interrupted request follows existing recovery and is not rerun from a regenerated preview. Seven-day receipt expiry remains separate from history and never permits automatic new-key execution.

Preview reads, undo previews and new full history reads use the existing five-second admission-to-complete-response deadline, eight unfinished physical reads and truthful freshness metadata. No new snapshot engine or import-refresh claim is added. Over-budget complete evidence returns explicit capacity/deadline failure with no usable review.

## Immutable operation history

`TaskConsolidationEvent` uses defaulted scalar fields compatible with the repository's additive SwiftData/CloudKit shape:

| Stored field | Meaning |
| --- | --- |
| `id: UUID` | Event identity; apply event ID is the operation ID. |
| `operationId: UUID` | Root apply operation for both apply and reversal events. |
| `kindRawValue: String` | `apply` or `undo`; unknown values are unavailable evidence. |
| `createdAt: Date`, `originScopeId: String` | Actual originating local commit time/store scope; never a cross-device deduplication claim. |
| `survivorTaskId: UUID`, `candidate1…candidate5: UUID?` | Scalar participant lookup, with one to five occupied candidate slots. |
| `payloadJSON: String` | Versioned immutable evidence, validated against scalar identity/participant fields. |

There are no task relationships, uniqueness constraints, cascades or mutable reversed flag. Task deletion does not delete history. One apply event and at most one uniquely observed reversal event make a valid local operation history; physical UUID collisions, conflicting/multiple reversals, missing apply events, unknown versions and malformed payloads yield unavailable/ambiguous diagnostics. Never select a first matching event or silently treat unreadable history as absent.

The apply payload stores caller reason/accounting, selected identities and observed direct/canonical mappings, exact changed-field before/after values, each participant's applied task r1, created occurrence UUID/kind/endpoints/date/fingerprint, required pre-existing chain evidence, and originating request/review references. It copies only fields needed for exact reversal; comments and unchanged candidate content remain on originals. The reversal payload references the immutable apply event and records actual attributable reversed effects and its own request identity. Neither history event embeds expiring receipt state or gets removed by receipt/link-evidence cleanup.

Encode dates as exact reference-date bit strings in reversible evidence; public timestamps use the existing formatter. Description null and raw metadataJSON bytes are preserved for restoration. Cap an event's UTF-8 payload at 256 KiB before effects; excessive changed values/accounting fail explicitly. This keeps one bounded history record without copying full comment bodies. Complete previews and current participant reads retain the larger existing response budgets.

An `o1` content token covers all physical apply/reversal event tuples for one operation, including multiplicity, exact payload and event values. Undo guards `o1` alongside task r1 and required relationship evidence. This avoids reminting task tokens for presentation history; historic pages/receipts remain byte-identical. Origin scope identifies where a request can be reconciled. Imported valid history can be reviewed locally with a new locally scoped undo key; cross-device simultaneous undo remains an outside-writer race.

## Planning, apply and reversal

`ConsolidationPlanner` is a platform-neutral value function producing `ConsolidationPlan` from bounded captured originals, a `TaskLinkGraphView` and validated caller choices. `ConsolidationHistoryProjection` decodes saved events and assesses current undo availability. `TaskConsolidationService` performs synchronous saved resolution and no-save domain application; `MCPConsolidationWriteAdapter` supplies owned services and the existing clean-context policy.

### Apply

1. Whole-shape validation and exact-key replay use the shared coordinator. Fresh work gets the existing durable payload binding/accepted receipt. Every post-await success/error path retains clean-context checks; preparation carries value identifiers only.
2. Inside the final nonawaiting MainActor owned phase, fetch the retained review and uniquely resolve every selected task (saved fetch limit two). Build fresh task r1s with complete comment/incidence coverage, required canonical paths and exact physical link evidence; match the review and revalidate the complete proposed graph. Resolve the common project by saved physical identity and reject missing/ambiguous project identity; same UUID spelling alone does not prove a common project. Independent writer/import fencing is not added.
3. One commit instant sets status-transition dates through `StatusEngine.applyTransition` only for unfinished candidates. Description/metadata edits affect only the survivor. Existing candidate chains to the survivor remain intact; unlinked candidates gain direct duplicate occurrences. Pure preview deltas mark new dates/occurrence IDs as assigned at commit rather than inventing saved identities. Preview freezes the permitted field transitions; commit-time values are explicitly shown as such in the review.
4. Combine per-source validated directives into one delta and project one final graph with the union of touched endpoints using the existing TaskLinkGraph rules; do not apply intermediate candidate plans to the store. Apply that combined delta through existing typed occurrence handling in the owned context, retaining actual newly created occurrence tuples for provenance. Extend the existing owned-apply helper to return created occurrence values to the caller without changing other callers' effects. Allocate unique operation/event identity, derive authoritative staged post-change task/comment/incidence values from the reviewed saved graph plus actual inserted/removed tuples and current owned task fields; compute applied r1s and encode history/participant results from those same values before the one domain/result save. Derive committed o1 from authoritative staged event values including the inserted apply/reversal event, never a saved-only precommit event fetch. Do not recapture saved-only incidence before this save: it excludes new occurrences. Restore and record raw statusRawValue as well as exact metadata/date values.
5. Insert apply history and stage the terminal receipt in the same context/save as all group effects. On failure, discard/roll back only the owned context and use the existing durable receipt probe: durable terminal means replay, proven accepted-before-commit means no-effect rejection, unavailable proof means uncertain/reconcile. Never compensate after a committed result or flush UI drafts.

The coordinator's group cases extend `PreparedMCPWrite` and `MCPWriteCommand.prepare/apply`; owned command services construct `TaskConsolidationService` with the same review source. The adapter uses the existing `makeCommitServices` policy hook. No command recursively executes per-task protected tools, no per-item keys are created, and no second reservation/coordinator state machine is introduced.

### Undo

Capture the unique apply/reversal events, all selected task r1s and exact required chain/created-occurrence evidence. Availability requires every selected current r1 to equal its recorded applied token, required original/link evidence to match, and the combined reversal graph to pass T-1734 validation. Compare current content, not temporal change history: edits restored identically can match again.

Fresh undo requires the retained reviewed reversal and matching current `o1`/task/link evidence inside the same owned phase. Restore only the changed survivor raw fields and changed candidate status/date triples; untouched terminal status dates stay untouched. Remove only the consolidation-created physical occurrences by their exact selectors using `TaskLinkOwnedApply` and its same-store removal evidence. Pre-existing chains are retained. Allocate a reversal event and stage its result with the group reversal in one save. Receipt failure/recovery and outside-writer/import limits are identical to apply.

If a valid reversal already exists, reconcile that saved state before demanding an expired review, return `already_reversed` with its event identity and no task/link changes, and retain a terminal result for a newly accepted key. Multiple or unreadable reversal events fail closed. No history event or original receipt is erased.

## Saved readback and native detail

Extend saved capture with immutable history event values fetched for selected participant scalar slots and closure by operation ID; validate all physical events for those operations within the capture boundary. For every represented operation, capture all participant tasks, complete comments/incidences and required canonical-path evidence in the same stable boundary and budgets before assessing undo. Dependency-closure tasks are supplementary evidence and never enlarge selectable query results. Missing/ambiguous/unreadable dependencies yield explicit unavailable undo assessment; incomplete event/history capture is a read failure. Current captures advertise explicit available history coverage, including an observed empty history; legacy retained captures keep absent/unavailable coverage rather than acquiring invented empty history. Fresh full `query_tasks` adds `consolidationHistory` with complete operation/reversal entries and current undo assessment. Summaries and retained prior results keep their existing shapes. Task r1 remains field/comment/link coverage; history reports separate operation o1 coverage.

History capture remains mandatory for new full reads of participants, even when output comment bodies are omitted. Storage/decode/identity failures are explicit unavailable outcomes; complete history over the response budget fails explicitly rather than paging away information needed for review. Unknown imported versions and malformed events associated with the participant remain visible diagnostics. Historical mappings are labelled separately from current graph canonical resolution.

`TaskConsolidationHistorySection` sits beside `TaskLinksSection` in all task-detail layouts. Its provider uses the same value-only participant/event/graph dependency capture. Add a native value-result entry point to the existing MCPReadCoordinator physical lifecycle and make its Foundation-only admission/deadline/terminal-selection dependencies available across platforms, retaining protocol/server/result-provider adapters behind macOS gating. TransitApp retains one app-lifetime coordinator: macOS MCP and native history share its eight physical slots; on iOS/iPadOS native history uses that same implementation without an MCP listener. Native preparation begins the same original five-second deadline; timeout/cancellation suppresses delivery while physical work holds its slot until cleanup. The native result has no retained review/publication roots and uses the source/generation view guard at delivery. TransitApp alone owns global coordinator start/stop. Tag admissions by native or listener instance; MCPServer stop/restart invalidates/cancels only its listener-owned requests and starts a new listener scope without resetting the shared count or disabling native history. Listener cleanup retains physical slots until each worker finishes; whole-app shutdown closes all admission. Do not create a separate counter, timer lifecycle or snapshot engine. Extract the saved persistent-history/generation boundary helper from MCPReadCaptureBuilder into shared consolidation capture support for this cross-platform provider; unavailable coherence proof returns unavailable history/assessment, with no production actor-only fallback and no new snapshot/admission engine. Its read-only saved value state follows `TaskLinkNativeDetailState` source/generation cancellation and save/remote-change refresh behavior, including the existing 100-ms coalescing. It displays reason, changes, source dispositions, participant references and reversal/undo availability. References use `TaskLinkNavigationResolver` and existing unresolved-reference styling. There are no native apply/undo controls or new navigation URLs.

## Error and result contract

| Failure | Result / effects |
| --- | --- |
| Bad group/edits/accounting, absent apply acknowledgment, wrong argument types | `INVALID_INPUT`, unaccepted, no domain effects. |
| Missing/expired/mismatched review | `CONSOLIDATION_REVIEW_UNAVAILABLE`, no domain effects; obtain fresh preview for a corrected new request. Retained replay bypasses this check. |
| Missing/ambiguous selected UUID, wrong project/canonical target, invalid graph | Specific identity/canonical diagnostic; accepted domain rejection after replay lookup, with no group effects. |
| Stale task/link/operation evidence | `REVISION_CONFLICT` with bounded current revisions and affected identities; accepted whole-group no-effect rejection. |
| Unreadable/multiple/malformed operation history | `CONSOLIDATION_HISTORY_UNAVAILABLE`; no inferred empty history or arbitrary undo. |
| Unsafe shared drafts | Existing pending-edit/acceptance/retry policy; read-only retained replay, no draft save/rollback. |
| Preview/publication/read capacity or deadline | Existing read capacity/timeout/unavailable classification; no usable review/partial history. |
| Provenance/result capacity or pre-save serialization | Resource-limit/serialization no-effect domain rejection when durability proves no commit. |
| Save/crash/cancellation/uncertain recovery | Existing `rejected`, `in_progress`, `uncertain`, acceptance and retryAction meanings; actual durable commitment wins. |

Modern result preparation adds these tools to provider contracts, schemas and protected recovery identity. Compact pre-effect fallback retains tool/key and known operation identity without unbounded record bodies. Participant record positions use existing task presentation with UUID-only unavailable navigation. All encodings are prepared/bounded before their respective publication or domain save; a post-effect wrapper failure uses preprepared recovery bytes without inventing no effect.

## Verification and requirement traceability

No validation runs are part of design work. Future implementation uses Swift Testing and `TestModelContainer`; disk-backed/reopen and injected-fault tests use existing coordinator seams. Seeded value generators and independent reference comparisons cover invariants without a new PBT dependency.

| Requirements | Design element / future verification |
| --- | --- |
| 1.1–1.4 | Strict wire/group validator and pure planner: bounds, normalization/collisions, canonical chains, combined graph rules, unchanged unrelated records. |
| 2.1–2.4 | Saved bounded preview and retained review: dirty saved-only captures, complete comments, mixed accounting, field attribution, unconditional acknowledgment, no preview writes. |
| 3.1–3.3 | Domain delta/event payload: conflicting detail fixture, preserved authors/dates/assignments, raw changed-value history and unchanged terminal dates. |
| 4.1–4.4 | Owned apply/undo: stale evidence, no participating interleave, draft isolation, one-save multi-task/link/history/receipt faults/reopen, explicit outside-writer race diagnostics. |
| 5.1–5.4 | Shared receipt/recovery: canonical key identity, dirty replay, expiry/restart, accepted interruption, lost response/encoding fallback, unchanged historic bytes/tokens. |
| 6.1–6.4 | Undo planner/service: exact review, comments/link conflicts, missing originals/events, pre-existing chains, raw date restoration, exact occurrence removal, repeated undo, history beyond seven days. |
| 7.1–7.3 | Modern output/fresh capture/native section: text/structured parity, mandatory history, current versus historical mapping, collision-safe navigation, cancelled/coalesced refresh. |
| 8.1–8.2 | Publication/read budgets and six-ticket scenario: expiry/capacity/cancellation before usable review, all mixed fields/statuses/comments, stale/fault/reversal outcomes. |

Generated properties: planning never changes its input; applied deltas affect only selected permitted fields/occurrences; eligible apply→undo restores exact changed fields/graph while retaining both history events; changed covered evidence prevents reversal; unrelated content is invariant; exact retained replay never executes domain effects. Examples supplement generators for malformed physical identities, imported history/canonical faults and actual owned-save durability.

## Risks requiring implementation evidence

- Risk: additive history model or one group history/receipt save behaves differently on a closed disk-backed store | Verify: early old-eight-entity-store reopen/migration and injected multi-record commit/reopen tests | If wrong: stop dependent implementation and revise the same-store model/save integration for design approval; do not add a distributed fence or partial compensation.
- Risk: representative complete group/history evidence reaches existing byte/deadline or the 256-KiB event cap | Verify: early boundary-sized fixtures with full-envelope accounting and explicit rejected outcomes | If wrong: preserve no-effect/unavailable behavior and bring any needed limit/storage change back through the design gate.

## Design gate

Does this design look good? Approval includes the shared retained-review workflow, immutable same-store apply/reversal event, 256-KiB event payload limit and exact whole-operation reversal, and authorises task planning only. Live bookkeeping, heavy commands and implementation remain held.
