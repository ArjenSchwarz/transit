# Batch Task Queries — Design

## Overview

Replace the MCP `query_tasks` array payload with a paginated object. Freeze encoded pages in a handler-owned cache; continuation reads cached text without accessing SwiftData.

## Architecture

All query preparation runs synchronously on `MCPToolHandler`'s MainActor, with no suspension between selection, comment fetches, serialization, and cache publication. This prevents UI mutations and sync callbacks from interleaving with snapshot construction. Store no live models in snapshots.

| File / component | Change |
|---|---|
| `MCP/MCPTaskQueryRequest.swift` | Parse initial versus continuation requests and validate options/selectors. |
| `MCP/MCPToolHandler+TaskQuery.swift` | Move `handleQueryTasks` and its lookup path into a focused extension; select tasks, serialize outcomes, and prepare pages. Expose only the handler dependencies and shared validation helpers needed by this extension at internal access. |
| `MCP/MCPTaskQuerySnapshotStore.swift` | MainActor cache of immutable page strings, expiry, byte accounting, and cursor lookup. |
| `MCP/MCPToolHandler.swift` | Own the store, dispatch queries, and expose `clearTaskQuerySnapshots()`. Keep the existing non-query tool paths unchanged. |
| `MCP/MCPToolDefinitions.swift` | Declare options, batch selectors, and cursor; document the response and limits. |
| `MCP/MCPTypes.swift` | Extend `JSONSchema` with optional `oneOf` and `additionalProperties`, preserving the factories used by other tools. |
| `MCP/MCPServer.swift` | Clear query snapshots and close admission in `tearDownCurrentServer` and the generation-checked `setNotRunning` callback; reset and reopen on listener launch. |
| `docs/agent-notes/mcp-server.md` | Update the query contract and snapshot lifecycle notes. |

Pattern / consumer audit:

| Existing call site | Needs equivalent? | Treatment |
|---|---|---|
| MCP list and display-ID paths call the handler's `taskToDict` | Yes | One query serializer uses explicit options and conditional comments. |
| Handler's serializer calls `IntentHelpers.taskToDict` | Yes | Reuse for summary/full fields; append comments only when requested. |
| `QueryTasksIntent` calls `IntentHelpers.taskToDict` twice | No | Preserve signatures and intent behavior; MCP envelope stays outside the shared helper. |
| `MCPServer` retains one handler through lifecycle changes | Yes | Clear cache and close admission on teardown or unexpected current-listener exit; reset and reopen on launch. |
| `MCPTestHelpers.decodeArrayResult` and MCP query tests | Yes | Add query-page decoding and explicit initial options; retain array decoding for unrelated tools. |
| Existing filter validation and `MCPQueryFilters.matches` | No new filter implementation | Extract existing validation/resolution without altering precedence or accepted values. |

## Components and Interfaces

### Request and response contract

Initial request:

```json
{"project":"Prism","type":"chore","detailLevel":"full","includeComments":false,"limit":100}
```

Continuation request:

```json
{"cursor":"<opaque token>"}
```

Successful list or single-ID response, inside the existing MCP text content:

```json
{"results":[{"taskId":"<uuid>","name":"Example","status":"idea","type":"chore","priority":"medium","lastStatusChangeDate":"<ISO8601>","description":null}],"nextCursor":"<opaque token>","expiresAt":"<ISO8601>"}
```

`results` contains task dictionaries for list/single lookup and outcome dictionaries for batches. The final or empty page has `nextCursor: null`. Dates retain existing ISO 8601 formatting. Summary and full task fields follow requirements 1.2–1.3, including the existing nested milestone shape.

Batch request and outcome examples:

```json
{"displayIds":[42,9999,42],"detailLevel":"full","includeComments":false,"limit":2}
```

```json
{"results":[{"index":0,"requested":{"displayId":42},"task":{"taskId":"<uuid>","displayId":42,"name":"Example","status":"idea","type":"chore","priority":"medium","lastStatusChangeDate":"<ISO8601>","description":null}},{"index":1,"requested":{"displayId":9999},"error":{"code":"TASK_NOT_FOUND","message":"No task matches displayId 9999"}}],"nextCursor":"<opaque token>","expiresAt":"<ISO8601>"}
```

UUID batch entries use `requested.taskId`; UUID text is preserved in `requested` for matching inputs, while returned task UUIDs use canonical uppercase `uuidString`. `index` is zero-based across the entire input, not per page. A repeated input produces another outcome at its own index. Success identity fields live in `task`, with `displayId` omitted when unallocated. Ambiguous identities use `AMBIGUOUS_TASK_ID`.

Parsing is presence-aware: JSON null is invalid for every provided selector/option. Only the existing filter keys plus the new options/selectors are accepted on initial calls; continuation accepts exactly `cursor`. Reject unknown keys. Reuse `IntentHelpers.parseIntValue` and `parseBoolValue` so booleans cannot become IDs or limits. Integers include exactly integral JSON numbers; strings and fractional numbers are rejected. Preserve existing zero/negative single-display-ID no-match behavior, and treat integer zero/negative batch display IDs as not-found outcomes.

At most one selector (`displayId`, `taskIds`, `displayIds`) is present. No selector means a filtered list. Batch selectors reject the presence of any list filter, including empty/null filter values. Validate all batch identifiers and the 1–100 length before accessing storage.

The schema's root contains `oneOf`: an initial object with required `detailLevel`, `includeComments`, and `limit`, and a continuation object requiring only `cursor`. Each branch has its own properties and `additionalProperties: false`. Initial branch property descriptions document the limit and selector/filter restrictions; runtime validation enforces them. Other tool schemas omit the new schema fields.

### Selection and serialization

For a list, use the injected `TaskFetching.fetchAllTasks`, apply existing resolved filters, and sort by uppercase task UUID string using ordinary lexicographic comparison. For single `displayId`, reuse `TaskService.findByDisplayID` and the same filters; not-found yields an empty page, duplicate display ID is a whole-query error.

For batches, fetch all tasks once through `TaskFetching`, build a UUID or permanent-display-ID index, and resolve inputs in order. Retain all matches per key so duplicate identities produce ambiguity outcomes instead of taking the first task. This uses the existing failure-injection seam and avoids adding fetch protocols or per-item database operations. No mutation or save occurs.

Serialize each unique resolved task once per query; repeated batch inputs reuse its dictionary. When comments are requested, fetch once per unique task, sort by `(creationDate, uppercase comment UUID)`, and copy comment fields into values. Comment omission never calls `CommentFetching`. Validate each page with `JSONSerialization.isValidJSONObject` and use throwing `data(withJSONObject:options:)` with no pretty printing. Do not use `IntentHelpers.encodeJSON`'s fallback for query pages. See [Foundation encoding API](https://developer.apple.com/documentation/foundation/jsonserialization/data%28withjsonobject%3Aoptions%3A%29).

### Snapshot cache

```swift
@MainActor final class MCPTaskQuerySnapshotStore {
    // Injectable monotonic and wall clocks, limits, and cursor generator.
    func publish(pages: [String], cursors: [String], deadline: ContinuousClock.Instant) throws
    func page(for cursor: String) throws -> String
    func clear()
}
```

At query start, capture a monotonic deadline of now + five minutes and wall-clock `expiresAt` of Date now + five minutes. Every page shares that expiry. Cursor strings are independent random UUIDs assigned to pages after the first; they are opaque dictionary keys, not encoded offsets. Pages embed their preallocated next cursor, so replay returns identical text. The first page is returned directly, while later pages stay cached until expiry even after the final page is read.

Prepare and encode every page before returning any result. Only after all task/comment reads, encoding, and capacity checks succeed is the snapshot published. If preparation reaches its deadline, fail without publication. An empty query still returns one empty page.

Limits: eight retained multi-page snapshots and 16 MiB total UTF-8 encoded page bytes. A query's encoded pages must also fit within 16 MiB even if it has only one page. Count encoded page bytes during construction and abort on overflow; cursor metadata is bounded separately by the encoded pages containing those tokens. One-page results need no retained snapshot. Purge expired entries before every initial query or continuation; expiry comparison is `now >= deadline` and reads do not extend it. Publish is atomic and capacity is rechecked after preparation.

Reject new multi-page queries when capacity is exhausted, without evicting unexpired snapshots. Store only encoded page strings and cursor mappings. `clear()` resets all accounting. Inject clocks and small capacity values for deterministic tests.

When an active listener tears down, close query admission and clear the cache synchronously before its first shutdown await. Requests already queued from that listener must fail while admission is closed. The `setNotRunning` callback also closes admission and clears snapshots after its existing generation check, covering unexpected exit and bind failure without letting a stale callback clear a replacement listener's cache. Listener launch clears snapshots before reopening admission. Direct handler tests start with admission open. No cursor survives a listener restart.

## Error Handling

Whole-query errors use `MCPToolResult.isError: true` and a JSON text object `{"error":{"code":"…","message":"…"}}`. Preserve typed failure categories during filter extraction, before formatting messages. Project lookup `storageFailure` and unexpected milestone fetch/lookup errors map to `QUERY_FAILED`; ambiguous project names and milestone names/display IDs map to `AMBIGUOUS_FILTER`. Project not-found or malformed filters map to `INVALID_INPUT`; milestone not-found keeps its existing empty-result behavior. Retain existing error messages. Existing unrelated tools keep their error format.

| Code | Trigger |
|---|---|
| `INVALID_INPUT` | Missing/invalid options, malformed selectors, conflicting selectors/filters, unknown fields, or cursor combined with any other field. |
| `AMBIGUOUS_TASK_ID` | Ambiguous single-display-ID lookup. In batches, ambiguity is an outcome error. |
| `AMBIGUOUS_FILTER` | Ambiguous project name or milestone name/display ID during filter resolution. |
| `QUERY_FAILED` | Storage, requested-comment, or JSON encoding failure; no results or cursor published. |
| `INVALID_CURSOR` | Malformed, unknown, expired, or cleared cursor; message instructs starting a new query. No tombstones needed to distinguish these causes. |
| `QUERY_CAPACITY_EXCEEDED` | Per-query byte limit or retained-cache limit reached; message suggests reducing scope/comments or retrying after expiry. |
| `QUERY_EXPIRED` | Initial preparation used the five-minute lifetime before publication; restart the query. |
| `QUERY_UNAVAILABLE` | Listener teardown has closed query admission; retry after server availability returns. |

Batch not-found and ambiguity are successful query outcomes. Failed task/comment reads fail the entire initial call. Continuations never refetch or silently replace a missing snapshot.

## Testing Strategy

Use Swift Testing, serialized MainActor suites, and `TestModelContainer` for integration fixtures. Add request parser, snapshot store, and handler query suites. Update existing query test calls to explicit options and decode `results`; preserve unrelated array tools and App Intent tests.

| Requirements | Checks |
|---|---|
| 1.1, 3.4–3.5, 4.3, 5.1 | Schema branches and parser agreement; missing/null/wrong-type options, boundaries, malformed arrays, mixed selectors, filters in batches, unknown keys, strict cursor-only requests. |
| 1.2–1.5 | Summary/full fields, nil description, empty/nonempty metadata, unallocated display ID, comments omission with throwing fetcher, comment order/ties/empty arrays, failures before publication. |
| 2.1–2.4 | Existing filters and validation with new options; single match, missing/nonmatching/duplicate ID; deterministic UUID ordering and empty page; typed project/milestone storage failures versus not-found and ambiguity. |
| 3.1–3.3 | UUID and display-ID batches, duplicates, original indexes across pages, missing/ambiguous matches, repeated task comment-fetch count. |
| 4.1–4.2, 5.2 | 182 full-detail chores in two pages; mutate/delete/create tasks and comments between pages, verifying frozen results. |
| 4.4–4.6 | Byte-identical cursor replay, fixed expiry/deadline boundary, malformed/unknown tokens, capacity rejection without eviction, atomic failed publication, initial expiry, accounting reset, stop/restart invalidation and admission fence; unexpected listener exit followed by restart rejects old cursors, while stale-generation callbacks preserve replacement snapshots. |

For pagination invariants, use deterministic generated result sets in Swift Testing across counts 0, 1, 99, 100, 101, 182, and 500 and limits 1, 2, 50, 100: concatenation equals input order, every page respects its limit, replay is identical, and repeated batch inputs remain distinct by index. No additional property-testing dependency is needed.

Run focused macOS suites during implementation using the Makefile's test tooling, then `make lint` and `make test-quick` at the implementation boundary. Full iOS/UI gates belong to pre-push review.
