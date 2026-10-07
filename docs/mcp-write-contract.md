# MCP write contract

Transit protects `create_task`, `create_project`, `create_milestone`, `add_comment`, `update_task`,
`update_task_status`, `update_milestone`, `delete_milestone`, `consolidate_tasks` and
`undo_task_consolidation`. Each requires `idempotencyKey`.
The four update/deletion tools also require the target's `expectedRevision` from a full read response.
Unknown fields and malformed inputs are rejected before accepting a key. Maintenance tools and App
Intents retain their existing input contracts.

Keys are case-sensitive and match `[A-Za-z0-9._:-]{1,128}`. Generate a fresh UUID for each logical write.
The namespace is one local store plus tool name, independent of JSON-RPC request ID, connection and
protocol session (the modern endpoint uses none). Request identity includes every argument except the key, including the original revision.
Object order is ignored; array order, Boolean versus number, absence versus null and explicit versus
omitted defaults remain significant. JSON numbers are compared by value.

For example, read `query_tasks` with
`{"displayId":42,"detailLevel":"full","includeComments":false,"limit":1}`. The bounded response
contains the task and revision in `results[0]`. Full reads always fetch complete comment state for
that revision; `includeComments:false` omits only the comment payload. Summary reads without comments
skip that fetch. A failed comment read aborts a full query without results or a cursor.

Then call `update_task` with:

```json
{"taskId":"<taskId from read>","name":"Reviewed","expectedRevision":"<revision from read>","idempotencyKey":"<fresh UUID>"}
```

If the response is lost, repeat those exact arguments with that same key. A retained completion
replays the original saved record, revision and metadata even after editing or deleting the target.
Reusing a retained key with different arguments returns `IDEMPOTENCY_KEY_REUSED` without mutation.

Protected responses retain JSON in MCP `content[0].text` and expose the same complete logical JSON, when interpretable, at `structuredContent.source.payload`. Retained malformed or over-limit JSON preserves raw text with unreadable structured evidence. Supplemental presentation lives separately; see the [versioned result contract](mcp-result-contract.md). Single-record committed responses include `contractVersion:1`,
`tool`, `idempotencyKey`, `outcome:"committed"`, `accepted:true`, `entityId`, the full saved `record`,
`completedAt` and `replayExpiresAt`. The record contains its `revision`. Status with a comment also
returns the full saved `comment`; both persist together. Milestone deletion returns `deleted:true`
and `recordBeforeDeletion`, including its pre-deletion revision; it has no surviving milestone revision.

Errors set MCP `isError:true` and contain `error:{code,message}`, `outcome`, `accepted` and `retryAction`.
Malformed protocol envelopes and unknown/disabled tools continue to use JSON-RPC errors.

| Outcome | Meaning | Action |
|---|---|---|
| `rejected` | Proven no effect from this requested write. Accepted rejections are retained with expiry. | `new_request_new_key` after correction; storage-unavailable/busy requests use `retry_same_request`. |
| `in_progress` | Matching accepted work is active. | `retry_same_request`. |
| `uncertain` | Storage cannot establish the whole operation's commitment. | `reconcile`; never automatically issue a fresh-key retry. |

`accepted` is true for a confirmed durable payload binding, false for proven non-acceptance, and null
when retry storage cannot determine earlier acceptance. For single-record tools, `REVISION_CONFLICT`
is a retained no-effect rejection containing `currentRecord` and its revision. Consolidation group
conflicts carry bounded `currentRevisions` and `affectedTaskIds`; group success uses participant and
operation evidence as described below. Inspect the corresponding current evidence before writing
with a new key. `INTERRUPTED_BEFORE_COMMIT` proves that an accepted operation's atomic domain/result save did
not complete; it is retained as a rejection rather than rerunning the operation.

Completed outcomes are retained for seven days from completion. Their absolute `replayExpiresAt`
does not extend on replay. Stop treating retries after that deadline as protected: once removed, a
key may be accepted as new work. Unresolved bindings never expire under this policy. Cross-device
deduplication is not provided, even when CloudKit synchronizes receipt records.

Revisions match `r1:[0-9a-f]{64}` and compare exact locally observed entity content. Task revisions
cover its own stored fields, assignments, comment content/membership and every physical active
incident link tuple under task-links-v1, including empty incidence. Opposite endpoint labels/status
and removal-evidence expiry do not invalidate that content token; parent project/milestone renames
also remain outside coverage. Historic retained tokens/results are never reminted. Milestone revisions exclude its task collection; project revisions
exclude child collections. No-ops keep their revision; restoring identical covered content restores
the same token. Tokens are neither timestamps nor monotonic counters. Edits not yet imported from
CloudKit cannot be detected, and later sync merges can still conflict.

## Standalone typed task links

`create_task` accepts optional addition-only `linkChanges`; `update_task` accepts up to50 explicit add/remove directives and exact `endpointPreconditions`. Public types are `blocks`, `blocked-by`, `relates-to`, `introduced-by` and `duplicate-of`. Direction matters for dependencies, attribution and duplicates; associations are symmetric. UUID endpoints remain canonical identities; duplicate links do not redirect writes or consolidate records.

An addition supplies `action:add`, `type` and `targetTaskId`. A removal supplies `action:remove`, exact `edgeId` and its `l1` occurrence fingerprint, never a replacement relationship set. The source uses its current graph-covered `r1`; guards for uniquely affected existing opposite endpoints use their current `r1`. Exact no-ops require the source guard but no unnecessary opposite guard. An exact malformed/dangling occurrence may be removed as repair without absorbing unrelated corruption. Separate immutable removal evidence recognizes an identical fresh-key removal no-op for seven days; expired/unavailable evidence fails closed. Re-additions receive new occurrence identities. No-op retries preserve timestamps and original evidence.

Whole input shape is validated before key acceptance. Saved reference/precondition/cycle/selector failures are accepted domain outcomes after exact retained replay lookup. The final phase resolves fresh saved state and applies task fields, physical link changes, separate removal evidence and terminal receipt in one owned local-context save. Participating MCP operations cannot interleave that synchronous phase; independent containers or sync/import writers may race, and projections diagnose available conflicts. This provides no global CloudKit atomicity or all-writer fence. UI drafts are neither returned by saved reads nor included in owned writes. Retained replay remains byte-identical and performs no repair or save.

`mutate_tasks` rejects `linkChanges` and `endpointPreconditions` throughout its whole-shape preflight, before any item is accepted. Existing non-link items still use graph-covered revisions and the participating owned-save policy. There is no link editor, automatic duplicate merge, relationship closure operation or deletion shortcut.

## Reviewed task consolidation

The four consolidation tools operate on saved local content. Select one survivor UUID and one to
five distinct candidate UUIDs from the same uniquely resolved project. The survivor must be the
terminal canonical task. An existing candidate chain is retained only when it already resolves to
that survivor; incompatible, dangling, cyclic or ambiguous canonical evidence fails closed.

1. Call `preview_task_consolidation` with `survivorTaskId`, ordered `candidateTaskIds`, a nonblank
   `reason` and candidate-keyed `preservation`. Every candidate must have a nonblank
   `retainedExplanation`, a nonempty `incorporated` list, or both. Each incorporated entry supplies
   `sourceDetail` and `survivorField` (`description` or `metadata`) and references an actual proposed
   survivor field change. Optional `survivorEdits` supplies a description replacement/explicit null
   or complete string-valued metadata replacement. Omission leaves that field unchanged.
2. Inspect the complete originals, preservation accounting and proposed field/link changes. The
   preview returns `reviewId`, `reviewRevision` (`p1:`) and `reviewExpiresAt`. It performs no domain,
   history or receipt write, key acceptance or display-ID allocation. Reviews share the ordinary
   eight-root retention capacity and 16 MiB complete representation limit, expire after five minutes,
   and are not extended or consumed by reads. Listener shutdown or clearing the retained index can
   retire the review earlier.
3. Call `consolidate_tasks` with the exact review reference, `preservationAcknowledged:true` and a
   fresh `idempotencyKey`. The server-held immutable review supplies all selected IDs and edits;
   the write does not accept an editable plan. Acknowledgment is required even for retention-only
   accounting. Saved participating evidence is revalidated before effects; a stale review requires
   a fresh preview and corrected new request.
4. To reverse, call `preview_task_consolidation_undo` with the original `operationId`. Inspect
   history and current whole-reversal availability. If available, call `undo_task_consolidation`
   with `operationId`, the exact undo `reviewId`/`reviewRevision` and a fresh key.

Apply abandons only unfinished candidates using the existing status/date rules. Done/Abandoned
candidates and survivor status/dates stay unchanged. Only the explicitly edited survivor description
and metadata change. Original tasks, assignments and comments remain in place. Compatible existing
chains and incoming links are preserved; new duplicate occurrences use the existing typed graph.

The committed protected result has `entityId=operationId` and group evidence including
`operationId`, `operationRevision` (`o1:`), `reason`, full saved `participants`, canonical `mappings`,
immutable `history` and `undoAvailable`/`undoUnavailableReason`. A reversal also identifies its
`reversalId`. Task participants retain their existing `r1` coverage; operation history has separate
`o1` coverage. Modern presentation uses task UUID references without inventing navigation URLs.

Whole reversal restores only the operation's recorded changed raw fields and removes only its exact
created occurrences. Current applied revisions, raw changed fields, history content and physical
multiplicity must match. Pre-existing links remain. There is no force/selective reversal and no
monotonic edit-history/ABA detector. Valid saved inverse history permits an already-reversed
assessment without another inverse event, even when the old temporary review has expired.

Apply or reversal effects, immutable event and terminal receipt share one owned local-context save
through the existing protected coordinator. Participating writers cannot interleave that phase;
independent contexts/imports may race. This is a local commitment guarantee, not a distributed
CloudKit transaction or global writer fence. Pending UI drafts are excluded.

Retry a lost response with the original tool, arguments and key. Retained receipt replay precedes
current review/content checks and preserves historical bytes. A wrapper failure after a possible
commit uses prepared compact recovery evidence; never infer no effect or rotate keys automatically.
Review expiry and seven-day receipt retention are separate from immutable operation history, which
has no independent time expiry. Encoded history is capped at 256 KiB, and complete evidence/results
are bounded rather than truncated. Missing/ambiguous/malformed evidence yields explicit unavailable
outcomes; incomplete saved history cannot be treated as an empty history.

Fresh full `query_tasks` includes saved consolidation history and current reversal assessment even
when comment bodies are omitted. Legacy retained pages and receipts keep their original bytes and
coverage. Native macOS/iPhone/iPad task details present saved reason, accounting, changes, paths and
reversal state read-only, with exact unique saved UUID navigation.

`mutate_tasks` does not accept consolidation operations. Installed-client validation, live CloudKit
schema verification and production activation are separate from this local feature.

## Application batch task mutations

`mutate_tasks` is one `tools/call`, not transport batching. Wire-level JSON-RPC arrays remain rejected.
Supply explicit `mode:"dry_run"` or `mode:"execute"` and 1–50 ordered `items`. Each item has a nonempty
opaque `itemId`, an `operation` (`update_task`, `update_task_status` or `add_comment`) and the original
protected tool's `arguments`. Task UUIDs must be unique after UUID normalization, item IDs must be
unique by exact spelling, and tool/key pairs must be unique. Updates require `expectedRevision`;
comments reject that field. Unknown fields, malformed safety values and wrong JSON types reject the
whole input before effects. Domain strings such as status, priority and type are validated per item.

Dry runs read saved local records, ignoring pending UI inserts, edits and deletions. They return
advisory proposals with `observation:"saved_local_store"` and `keyState:"unchecked"`; they neither
reserve keys nor establish replay availability. Full comment state determines the canonical `r1`
even when comment payloads are omitted. A later save can invalidate that revision.

Execution applies items in order and advances only after established committed evidence. The first
rejection, active or uncertain outcome, pending-edit stop, unavailable evidence or cancellation stops
later items. Each successful item commits independently; the batch is not a transaction. There are
no automatic retries or rollbacks of earlier commits. `not_attempted` describes this invocation,
not the history of that key. Original per-item JSON, text, optional `isError`, revisions and retry
instructions remain authoritative; aggregate `isError` does not replace them.

There is no whole-batch receipt or replay key. Recover each attempted item with its original tool,
arguments, key and originating local store. Regrouping items does not change protected request
identity. An identical batch retry may replay earlier committed items and execute previously
`not_attempted` items, stopping again at the first unsuccessful item. Exclude a retained no-effect
rejection, or correct its arguments with a fresh key, before expecting later items to proceed. A historical canonical replay certifies its saved outcome, not current task contents.
A removed or absent receipt does not prove that the original operation had no effect. If new duplicate closures require the canonical task to still match the plan, reconcile current
canonical records and original evidence before submitting those closures. Historical replay does not
establish that current-state condition.
Respect each known seven-day expiry and retain the original first-submission time. When that time
or acceptance evidence is lost, reconcile rather than assuming a fresh execution is safe. Retrying
a removed key after expiry can repeat effects, including comments. Never rotate keys automatically
for unknown outcomes.

Lost responses and cancellation do not undo effects. If aggregate encoding fails after dispatch,
the already prepared `summary:"serialization_failed"` fallback contains the correlated original
indexes, operations, tools, keys and UUIDs, with unestablished effect evidence. Reconcile those keys;
do not infer no effect from a failed response. Installed-client validation and activation remain
deferred to post-merge MacBook checks.

## Recovery when local retry storage is unreadable

If protected writes return `OUTCOME_UNCERTAIN` because guards or the scope identity cannot be read,
stop automatic writes and new-key retries. Read tools remain available for reconciliation when the
domain store is readable.

1. Quit Transit to release its store lock. Preserve and back up the SwiftData store, its companion
   files, and the complete MCP sidecar beside it, including the original `scope` and `guards` files.
2. Reconcile the original operation against domain records and retained receipt evidence. A missing
   target or receipt does not prove that the operation never committed; a later edit or deletion may
   explain the current state.
3. Restore binding metadata only from verified original evidence for this same local store. The scope,
   tool, key, canonical request and receipt UUID must retain their original association; a terminal
   guard must retain its original expiry. If the original identity or binding cannot be established,
   keep writes blocked and seek manual recovery. Restoring a file alone does not prove a no-effect outcome.
4. Restart Transit and retry the exact original request with its original key. A valid retained receipt
   can replay its result. If the outcome remains uncertain, retain the binding and continue reconciliation.

Do not delete guards, clear the sidecar, generate a new scope, or reset/reassign keys as a shortcut to
unblock writes. These actions discard acceptance evidence and can duplicate an operation that committed.
Transit exposes no force-retry or key-reset tool. Unresolved bindings remain protected without an expiry.
