# MCP write contract

Transit protects `create_task`, `create_project`, `create_milestone`, `add_comment`, `update_task`,
`update_task_status`, `update_milestone` and `delete_milestone`. Each requires `idempotencyKey`.
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

Protected responses retain JSON in MCP `content[0].text` and expose the same complete logical JSON, when interpretable, at `structuredContent.source.payload`. Retained malformed or over-limit JSON preserves raw text with unreadable structured evidence. Supplemental presentation lives separately; see the [versioned result contract](mcp-result-contract.md). Committed responses include `contractVersion:1`,
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
when retry storage cannot determine earlier acceptance. `REVISION_CONFLICT` is a retained no-effect
rejection containing `currentRecord` and its revision. Inspect that record before writing with a new
key. `INTERRUPTED_BEFORE_COMMIT` proves that an accepted operation's atomic domain/result save did
not complete; it is retained as a rejection rather than rerunning the operation.

Completed outcomes are retained for seven days from completion. Their absolute `replayExpiresAt`
does not extend on replay. Stop treating retries after that deadline as protected: once removed, a
key may be accepted as new work. Unresolved bindings never expire under this policy. Cross-device
deduplication is not provided, even when CloudKit synchronizes receipt records.

Revisions match `r1:[0-9a-f]{64}` and compare exact locally observed entity content. Task revisions
cover its own stored fields, assignments and comment content/membership; parent project/milestone
renames do not invalidate the task. Milestone revisions exclude its task collection; project revisions
exclude child collections. No-ops keep their revision; restoring identical covered content restores
the same token. Tokens are neither timestamps nor monotonic counters. Edits not yet imported from
CloudKit cannot be detected, and later sync merges can still conflict.

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
