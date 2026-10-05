# MCP result contract version 1

Transit's macOS endpoint supports MCP `2026-07-28` only. A tool result keeps the original text and optional `isError` and adds an independent structured wrapper. Output schemas advertised by `tools/list` validate `structuredContent`, not the entire JSON-RPC response.

```json
{
  "jsonrpc": "2.0",
  "id": "read-1",
  "result": {
    "resultType": "complete",
    "content": [{"type": "text", "text": "{\"results\":[],\"nextCursor\":null,\"expiresAt\":\"2026-10-04T00:05:00Z\"}"}],
    "structuredContent": {
      "contractVersion": 1,
      "source": {"kind": "json", "payload": {"results": [], "nextCursor": null, "expiresAt": "2026-10-04T00:05:00Z"}},
      "presentation": {"evidence": "established", "links": []}
    }
  }
}
```

This illustrative empty frozen-page result omits `isError` and capture metadata. Actual covered reads also carry their original `_meta` capture/freshness data outside `structuredContent`. Use the advertised schema and actual result rather than assuming metadata is absent.

## Original source and presentation

| Source kind | Payload | Meaning |
| --- | --- | --- |
| `json` | Complete original JSON value, including scalar/array roots | Parseable provider evidence; preserve unknown fields and original types. |
| `text` | Original string | Provider explicitly declared plain text. Do not guess JSON intent. |
| `unreadable` | Absent | Retained JSON cannot be interpreted; exact raw text remains in `content[0].text`. |

`presentation.evidence` is `established` or `unestablished`. A syntactically readable source can still have contradictory or unsupported outcome evidence; do not infer commitment from readability. Supplemental `errorCategory`, `recovery` and `links` never overwrite original payload fields. Unknown saved fields named `presentation`, `source` or `contractVersion` stay inside `source.payload`.

Preserve absent versus null, Boolean versus number, unknown fields and exact numeric tokens. The optional result-level `isError` preserves its original absent/false/true state. Text is the unchanged original string, including whitespace/newlines; JSON string escaping in the outer transport does not change that string. Native consumers can round numbers, so retain raw text when exact numeric identity matters.

Parser inputs allow at most 32 nested object/array containers (root container counts one; scalar counts zero). Generated JSON over this limit fails with a resource-limit error. Retained over-limit or malformed JSON becomes unreadable with unestablished evidence; it is not rewritten or reparsed from live records. The complete modern wrapper is not subject to a claimed 32-level output limit.

## Replay, frozen pages and saved fields

[Protected writes](mcp-write-contract.md) replay stored T2380 result JSON, original error state, revisions, acceptance and retry information without rewriting receipts, rereading current entities or extending expiry. A new JSON-RPC request ID changes only response correlation. Cursor continuations similarly reuse frozen text, logical pages, revisions and capture metadata; wrappers cannot remint revisions or extend retention.

Current task `r1` covers canonical task fields, comment content/membership and every incoming/outgoing physical active link tuple, including repeated and malformed imported tuples. `linkContract:task-links-v1` explicitly covers empty incidence too; tokens from the pre-link contract therefore conflict on fresh task writes even when no links exist. `includeComments:false` and omitted link bodies do not remove that evidence from revision coverage. Current results advertise `revisionCoverage:task-fields-comments-links-v1` and `graphCoverage:available` when captured evidence exists. Historical results retain their original token and bytes; explicit legacy results with absent graph evidence report missing coverage, never an invented empty graph.

Opposite endpoint labels/status, duplicate resolution, blocker assessment and seven-day removal-evidence expiry are observations outside the task content token. Full relationship observations come from the same frozen saved capture; cursor replay does not refresh them. Parent project/milestone display labels are also associated data outside task revision coverage. Compare saved mutation-owned fields to a full read at the same covered revision, not to later live labels.

| Protected path | Existing normalization authority |
| --- | --- |
| `create_task`, `create_milestone` | Services trim names; provided descriptions pass through, including surrounding whitespace/newlines. |
| `create_project` | ProjectService trims name; description passes through, with the existing empty-string default when omitted. |
| `update_task` | TaskUpdateValidator trims name/description using whitespacesAndNewlines. Omitted description is unchanged; empty after trimming clears it. Internal newlines survive. Metadata replaces/clears under the validator. |
| `update_milestone` | MCPWriteCommand trims name/description. Omission leaves description unchanged; empty after trimming clears it. |
| `add_comment`, status update with comment | CommentService trims content and author; existing status-command validation applies. |

The serializer adds no second normalizer. Historical absence/null distinctions remain intact.

## Errors and recovery

Original `error.code`, message, `outcome`, `accepted` and `retryAction` remain authoritative evidence. Category is supplemental, not a new outcome namespace or a retry guarantee. Protocol-invalid requests produce HTTP/JSON-RPC failures rather than tool errors.

| Category | Read recovery / caller action |
| --- | --- |
| `invalid_input`, `not_found`, `ambiguous_identity`, `revision_conflict`, `key_conflict` | Correct input or inspect evidence; no automatic read retry promised. |
| `storage_failure`, `incoherent_capture`, `admission_busy`, `deadline_exceeded`, `retention_capacity`, `serialization_failure` | `retry_identical_read` for reads; failure publishes no successful records/cursor/snapshot. |
| `invalid_cursor`, `expired_cursor` | `restart_read`; start a fresh read rather than reusing the invalid retained view. |
| `outcome_uncertain` | Reconcile the original mutation and protected key; never assume no effect or use a fresh key automatically. |
| `unclassified_historical`, `internal_failure` | Inspect source and provider evidence; no blanket retry promise. |

For protected writes, `recovery.direction:follow_source` means obey the preserved known `retryAction`; `reconcile_original_write` includes the original tool and key. Unsupported/contradictory evidence requires reconciliation even if it resembles rejection. Unprotected maintenance uses `reconcile_maintenance` and its original tool, without an invented protected key; inspect current state with a fresh `scan_duplicate_display_ids` before deciding further effects.

A mutation's complete request-correlated fallback bytes must be prepared before effects. If final encoding fails after effects, selection uses those bytes without calling the failed encoder again; effect evidence is unestablished. Application-batch recovery can retain ordered original indexes/tool/keys/UUIDs, while compact fallback omits unbounded itemIds, raw records and links. This common seam does not claim T2384 production integration or define its batch outcomes.

## Links

Task/project entries in `presentation.links` associate `entityType`, UUID `entityId` and RFC6901 `sourcePath` with frozen source evidence. Each currently has `availability:unavailable` and `reason:navigation_not_supported`. No guessed URI is emitted. T572 entity-opening navigation is a separate feature; unavailable links remain deterministic on replay.

## Latest-only request contract

Use one JSON-RPC object per `POST /mcp`, with `Content-Type: application/json`. Requests require non-null string or signed 64-bit integral IDs, object `params` and:

```json
{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}
```

Optional clientInfo, if supplied, must include string name/version. Send `MCP-Protocol-Version: 2026-07-28` and `Mcp-Method` matching the body method. `tools/call` additionally requires `Mcp-Name` matching the tool name. Ordinary responses require acceptable `application/json`; subscriptions require acceptable `text/event-stream`. Header name matching is case-insensitive, values remain validated. Request bodies are limited to 1 MiB.

Methods are `server/discover`, `tools/list`, `tools/call` and `subscriptions/listen`. Discovery and sorted tool lists include `resultType:complete`, `ttlMs:0` and `cacheScope:public`. Maintenance availability changes are reflected in the next list. There is no initialization handshake, session ID, GET listener or wire-level JSON-RPC batch. An application batch is one `tools/call` under its owner's separate feature contract.

| Rejected input | HTTP behavior |
| --- | --- |
| Disallowed Origin/Host | 403 before body capture/dispatch |
| Non-POST method | 405, Allow POST |
| Unsupported content type / response negotiation | 415 / 406 |
| Malformed JSON, nesting/range/shape errors, missing/mismatched metadata/headers, unavailable tool, client notification | 400, no effects |
| Unsupported protocol version | 400 with supported version list |
| Unknown RPC method, including legacy initialize, after valid modern metadata/headers | 404, method-not-found; an invalid envelope rejects earlier |
| Oversized body | 413 |

Loopback-only listening remains `127.0.0.1`; missing Origin is permitted, non-loopback Origin/Host is rejected. The transport expands no remote access.

`subscriptions/listen` uses `params.notifications:{toolsListChanged:true}` plus request metadata, ID and matching headers. The first SSE message is `notifications/subscriptions/acknowledged`; changes carry the original subscription ID and only acknowledged supported filters. Pending invalidations coalesce without evicting the first acknowledgement. Disconnect/cancellation removes the request registration; graceful server closure may finish with a complete result. No session IDs, event IDs or resumability are issued.

## Bounds and readiness

Covered reads retain the five-second deadline and eight unfinished physical-read admission slots across listener restarts. Cancellation suppresses late delivery/publication but does not free a physical slot until work completes. Ordinary/reusable retained data retains its own five-minute, eight-snapshot and 16-MiB contracts; structured/text/envelope duplication is charged. Capacity/deadline failure does not publish partial success or invalidate existing retained entries.

Actual installed Codex surfaces, Claude Code and Claude Desktop compatibility remains **unverified**. The owner explicitly deferred AC6.3 to post-merge MacBook testing at Sentinel_c0dbfe3212888191bc01744c855f67bb. Synthetic loopback evidence proves local protocol behavior only. Later validation must record modern discovery/list/call and native parsed structured consumption per intended surface, and subscriptions for surfaces opting in. This deferral permits merge after required review/checks; it does not authorise client setup or deployment here.
