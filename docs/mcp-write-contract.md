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

These outcome and revision semantics are shared vocabulary for T-2384. They introduce no batch
mutation application or dry-run behavior. Wire-level JSON-RPC arrays are rejected. A T-2384 application batch, when delivered by its owner, is one tools/call with its separate per-item effect policy.


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
