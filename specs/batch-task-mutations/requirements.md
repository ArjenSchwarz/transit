# Requirements: Batch Task Mutations

Ticket: T-2384  
Review status: approved in parent at `Sentinel_35dae4e67398819184369b41649ec75b`, including final transport clarification in commit `9b5122c`.

## Introduction

Agents consolidating tasks need to preview and submit a canonical task update, duplicate status changes and reasons with fewer round trips. This feature provides explicit ordered task operations with item-level saved outcomes and retry protection in the originating local store. It makes partial progress visible so interrupted work can be reconciled without repeating effects.

## Non-Goals

- Whole-batch atomicity, rollback of earlier committed items, compensation, or global CloudKit transactions.
- Automatic duplicate matching, canonical-task selection, duplicate links, or dependence on T2381.
- Task creation, project/milestone mutation, arbitrary tool invocation, App Intent batching, or a new authorization model.
- Multiple operations on the same task in one submission, implicit revision chaining, or merging property and status edits into a new combined operation.
- New durable batch-key storage, longer T2380 retention, or automatic resubmission after expiry/across stores.
- JSON-RPC transport batch changes, protocol-version migration, or extending T63's five-second read deadline contract.

## Requirements

### 1. Explicit Bounded Operations

**User Story:** As an MCP caller, I want one domain batch of explicit task operations, so that I can submit a consolidation plan efficiently.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL expose a domain batch tool accepting an explicit dry-run or execute mode and 1–50 ordered items supporting only `update_task`, `update_task_status`, and `add_comment`; a domain batch SHALL remain one tool call independent of any JSON-RPC transport array.  
2. <a name="1.2"></a>Each item SHALL identify its target by `taskId` UUID, declare a non-empty unique client `itemId`, and supply an explicit `idempotencyKey` matching `[A-Za-z0-9._:-]{1,128}`; update and status items SHALL also supply `expectedRevision` matching `r1:[0-9a-f]{64}`.  
3. <a name="1.3"></a>WHEN the outer request or any item's shape is invalid, including unsupported fields/operations, malformed safety inputs, duplicate item IDs, duplicate tool/key pairs, duplicate target UUIDs after UUID normalization, or an out-of-range item count, the system SHALL reject the entire request before executing any item and SHALL report validation diagnostics correlated by input index and item ID when usable, without accepting keys. Wrong JSON types and malformed safety formats SHALL be whole-request shape failures; invalid status/type/priority values and missing status-comment authors SHALL be item domain failures.  
4. <a name="1.4"></a>The system SHALL retain each operation's existing field semantics and normalization, including atomic status-plus-comment with its required author, property-update milestone validation, and standalone `add_comment` without a revision precondition; a batch SHALL NOT weaken required inputs or infer target tasks from descriptions.  
5. <a name="1.5"></a>WHEN a new item is attempted, the system SHALL validate unambiguous task identity, supported references, current local preconditions, and the existing server/store write-availability restrictions before committing its domain effect; a lookup, comment-fetch, or validation failure SHALL NOT be interpreted as a missing permission or empty successful record.  

### 2. Advisory Mutation-Free Preview

**User Story:** As an MCP caller, I want to inspect every proposed effect before submission, so that I can correct invalid or stale plans.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN mode is dry-run and the request shape is valid, the system SHALL validate every item's current local identity, references, preconditions, normalization and domain constraints without stopping at the first invalid item, and SHALL return ordered valid/invalid/unavailable diagnostics with client mappings and observed record/revision when obtainable.  
2. <a name="2.2"></a>A dry run SHALL create or modify no domain records, timestamps, comments, display-ID allocations, durable keys, receipts or guard state, SHALL perform no cleanup/recovery or save of pre-existing pending edits, and SHALL leave pending edit state unchanged.  
3. <a name="2.3"></a>A valid preview SHALL describe the normalized proposed changed fields and status/comment effects without inventing committed timestamps, comment identities, saved revisions or replay expiries; invalid/unavailable previews SHALL distinguish caller mistakes, revision conflicts and failed state validation.  
4. <a name="2.4"></a>The preview SHALL explicitly report that retry-key state is unchecked, that it reserves neither keys nor target revisions, and that submission independently revalidates new writes or replays retained outcomes; preview validity SHALL NOT promise write availability, durability, identical later results, or imported CloudKit freshness.  
5. <a name="2.5"></a>WHEN comment bodies are excluded from observed preview records, the returned task revision SHALL remain the authoritative comment-covered `r1`; projection SHALL NOT remint a revision from the visible fields.  

### 3. Ordered Per-Item Application

**User Story:** As an MCP caller, I want explicit partial-commit semantics, so that I know which effects survived a failed submission.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN mode is execute and the request shape is valid, the system SHALL attempt items in input order, advance to the next item only after an understood authoritative committed outcome, and retain each committed item independently; it SHALL NOT claim whole-batch or cross-device atomicity.  
2. <a name="3.2"></a>WHEN an attempted item returns rejected, in_progress or uncertain, the system SHALL stop further attempts and return every remaining item as not_attempted with the blocking item ID; transient rejection/in_progress/uncertain responses SHALL NOT be described as durably terminal unless their authoritative outcome establishes that; earlier committed effects SHALL remain committed.  
3. <a name="3.3"></a>WHEN status and an accompanying comment form one item, the system SHALL preserve T2380's both-or-neither persistence and replay boundary; an uncertain outcome SHALL refer to the whole item rather than permit a partial status/comment result.  
4. <a name="3.4"></a>WHEN a new update/status item's locally observed revision has changed since preview or another read, that item SHALL return `REVISION_CONFLICT`, current record/revision and no accompanying effect; prior successes SHALL NOT override this conflict.  
5. <a name="3.5"></a>WHEN execution is interrupted before later items begin, the system SHALL perform no background continuation of unstarted items; unavailable response delivery SHALL NOT imply that already attempted items had no effect. Interruption SHALL mean observed cancellation or execution failure, not merely a caller timeout or lost response whose cancellation the server has not observed.  

### 4. Item Keys, Replay and Safe Continuation

**User Story:** As an MCP caller, I want existing retry guarantees for each item, so that missing batch responses do not duplicate comments or edits.

**Acceptance Criteria:**

1. <a name="4.1"></a>Each item's key SHALL retain T2380's local-store/tool namespace and canonical operation-argument binding; outer mode, ordering, client item ID and any batch correlation ID SHALL NOT create a new durable namespace or change the underlying operation payload. UUID normalization SHALL serve collision detection/mapping only and SHALL NOT change original argument spelling used for receipt binding; a differently spelled UUID argument under a retained key remains subject to T2380 payload comparison.  
2. <a name="4.2"></a>WHEN a retained item key is retried with identical operation arguments, the system SHALL return its authoritative saved outcome before checking current target existence, revision or domain validity, even after later edits/deletion or restart; changed arguments under that key SHALL return `IDEMPOTENCY_KEY_REUSED` with no new effect.  
3. <a name="4.3"></a>WHEN a completed item is replayed, the system SHALL preserve its original normalized record/revision, accepted/outcome/retryAction fields, original completion/expiry, and missing/null distinctions; replay SHALL NOT reread live state to replace them or extend the guaranteed seven-day window.  
4. <a name="4.4"></a>WHEN simultaneous submissions share an identical item key/request, the system SHALL preserve T2380's at-most-one logical effect and committed/rejected replay, in_progress or uncertain response; one response's uncertainty SHALL NOT authorize a second key for that effect.  
5. <a name="4.5"></a>The batch contract SHALL instruct callers to retain item arguments, keys and returned expiries, retry identical retained requests in the originating store after response loss, and stop for reconciliation when commitment is uncertain or a replay guarantee is expired/unavailable across store scope; the system SHALL NOT automatically rotate keys, repair guards or apply compensation. WHEN the first response was lost and no replay expiry is known, callers SHALL retain the original submission time as reconciliation context and SHALL NOT assume indefinite replay protection; absent/removed receipts SHALL NOT be presented as proof that the original effect never happened, and expired removed keys MAY execute as new requests under T2380.  
6. <a name="4.6"></a>WHEN a retained item conclusively rejected without effect is corrected, the system SHALL require a new item key for changed arguments; not_attempted items SHALL have no new key acceptance attributable to that batch and MAY be resubmitted with their unchanged keys.  
7. <a name="4.7"></a>The outer batch SHALL provide no durable whole-response replay guarantee; an identical batch retry MAY replay earlier items and execute previously not-attempted items, SHALL still stop on its first unsuccessful item, and SHALL describe this continuation explicitly. A replayed canonical update SHALL NOT certify its current contents; callers requiring a current canonical-state condition before new duplicate closures SHALL reconcile current state before submitting those closures, rather than expect receipt replay to revalidate it.  

### 5. Correlated Records and Machine-Readable Outcomes

**User Story:** As an MCP caller, I want a complete item mapping and saved outcomes, so that I can verify partial progress without additional successful-write readbacks.

**Acceptance Criteria:**

1. <a name="5.1"></a>A completed batch response SHALL identify its contract version, mode and per-item atomicity, return an entry for each input item in input order with client item ID, operation, key and target UUID, and identify any stopping item and whether all items committed; preview responses SHALL clearly identify preview validity instead of commitment.  
2. <a name="5.2"></a>Every attempted execution entry SHALL preserve the complete authoritative T2380 outcome including unknown JSON fields, original result text bytes, and original item-level result `isError` separately from aggregate `isError`, preserving committed/rejected/in_progress/uncertain classification, accepted true/false/null, saved records/revisions/comments when present, error code/currentRecord/retryAction and terminal replay expiry when present; batch-local not_attempted entries SHALL NOT fabricate a receipt, saved record or expiry.  
3. <a name="5.3"></a>WHEN state cannot be read or verified, or the aggregate result cannot be serialized/delivered, the system SHALL stop further execution unless an understood authoritative result proves commitment, return remaining items as not_attempted when delivery is possible, preserve available original item result text/error flag without inventing a receipt outcome, and report an explicit aggregate failure; the system SHALL NOT present an empty successful batch, mark committed items rejected, fabricate certainty, or recommend a fresh key for an unresolved attempted effect.  
4. <a name="5.4"></a>The batch result SHALL expose a structured result value through the T2383 result contract and compatible JSON text with the same semantic batch data; adaptation of nested stored outcomes SHALL preserve their historical meaning without rewriting their receipts, and error categories SHALL NOT override their retryAction.  
5. <a name="5.5"></a>Execution responses containing any rejected/in_progress/uncertain/not_attempted item and previews containing any invalid/unavailable item SHALL set tool-level `isError` true; full commits and fully valid previews SHALL NOT set `isError` true. Protocol/outer-input failures SHALL remain distinguishable from domain item failures.  
6. <a name="5.6"></a>Saved and replayed item records SHALL identify the commit-time snapshot rather than promise equality with later live readback; existing text payloads, frozen cursor revisions and canonical comment-covered `r1` semantics SHALL remain compatible.  

### 6. Verifiable Recovery and Compatibility

**User Story:** As a maintainer, I want observable contract tests, so that batches cannot weaken existing writes or concurrent read guarantees.

**Acceptance Criteria:**

1. <a name="6.1"></a>Automated verification SHALL cover the preview/submission of one canonical description update followed by distinct duplicate status-plus-reason items, and SHALL verify ordered saved records and comment identities without automatic duplicate decisions.  
2. <a name="6.2"></a>Automated verification SHALL cover zero-effect dry runs with pending edits, malformed whole-request rejection, same-task/alias/key collisions, stale and ambiguous targets, reference and comment-fetch failures, stop-after-failure, interrupted iteration, and exact mapping of unattempted items.  
3. <a name="6.3"></a>Automated verification SHALL cover matching/mismatched item retries, batches regrouping the same underlying item, shared-key concurrency, later edits/deletion before replay, retained no-effect rejection, restart recovery, uncertain commitment, expiry limitations including a lost first response with unknown expiry and retry after receipt removal, and aggregate serialization/delivery failure after an item commits.  
4. <a name="6.4"></a>Automated verification SHALL preserve standalone write behavior and the transport ordering supported by the approved T2383 protocol contract, comment-covered revisions with omitted bodies, frozen snapshot/cursor records, and semantic text/structured parity for historic receipt outcomes; these checks SHALL NOT require legacy JSON-RPC arrays.  

## Approved Requirements Gate

Approved choices: 1–50 operations; UUID-only task selectors; at most one operation per task; stop on first unsuccessful item; advisory all-item preview with retry-key state unchecked; standalone comments retain the existing absence of revision checking. These choices are settled for design; changes require reopening the requirements gate.

The full-spec scope and feature name were approved in the parent conversation at `Sentinel_4fd40b3fecf48191a57ce03897d3e7ec`. Requirements were approved at `Sentinel_35dae4e67398819184369b41649ec75b`; design was approved at `Sentinel_717be95229c48191a7c41b6e5e467e4c`; task plan and conditional implementation were approved at `Sentinel_edf7fd12288c819192ad45a04154372a`; dependent work awaits its documented delivery/ownership/test-slot conditions.
