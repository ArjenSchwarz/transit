# MCP bounded reads and freshness

Covered macOS reads describe a completed capture of **saved local data**. A capture timestamp or recent import is not proof that every remote edit has arrived. Use the current advertised tool schema and the [modern transport/result contract](mcp-result-contract.md) for request metadata, headers and structured results.

The server allows five seconds from the read's original admission through complete response preparation. Import observation, store capture, transformation and encoding share that budget. An internal 4,850 ms selection cutoff reserves time for response completion. Client/network delivery time is outside this server budget. Eight unfinished physical reads are admitted per process; listener restart does not reset that count. A timeout ends delivery, while its physical work retains capacity until cleanup. Native saved consolidation history and macOS MCP reads share this app-lifetime capacity and original deadline. Listener stop/restart closes only that listener's admission and delivery; it does not disable native history or release unfinished workers.

## Policy and import limits

New reads default to `readPolicy: "refresh_if_needed"`. This can observe positively applicable imports already in flight for at most two seconds within the remaining total budget. The current SwiftData integration has no supported force-pull or provable import-to-capture visibility mechanism; it reports `unavailable` refresh and honest `unknown` freshness when applicability cannot be established. Heartbeat writes and notification arrival are not import proof.

`readPolicy: "cached"` skips import waiting and reports `not_requested`. It still creates a new saved local capture. Inactive sync skips waiting under either policy and reports `syncState: "inactive"`, `assessment: "not_applicable"`, and `lastImportedAt: null`. A failed or unavailable refresh can accompany a successful complete local read. A refresh wait timing out is distinct from the entire read returning `READ_TIMEOUT`.

## Capture metadata

Read metadata is outside `structuredContent`, at `result._meta["me.nore.ig.transit/read"]`. A successful capture has:

```json
{
  "asOf": "2026-10-03T15:00:00.000Z",
  "snapshotId": "opaque-capture-id",
  "freshness": {
    "syncState": "active",
    "assessment": "unknown",
    "assessedAt": "2026-10-03T15:00:00.000Z",
    "lastImportedAt": null,
    "evidence": "none",
    "recentImportThresholdMs": 30000
  },
  "read": {
    "policy": "refresh_if_needed",
    "refreshOutcome": "unavailable",
    "budgetMs": 5000
  }
}
```

`asOf` is the completed local capture time, in UTC with millisecond precision; `assessedAt` is fixed to that same time. `snapshotId` is opaque. `recent_import` means a positively relevant successful import was visible to the selected capture within 30,000 ms; `stale` means older known evidence; `unknown` means absent, unreliable or unprovable evidence. `completed_import` is the evidence value for a proven relevant import; otherwise it is `none`. Later failed imports do not erase a valid prior success timestamp. None of these values promise global freshness.

Refresh outcomes are `not_requested`, `recent_import`, `import_observed`, `failed`, `timeout`, and `unavailable`. Successful empty selections still carry capture metadata. Failed required fetches and incoherent captures are errors, not empty success.

## New captures and frozen replay

These are **tool argument objects**, to be placed inside a valid modern `tools/call` request:

```json
{"detailLevel":"summary","includeComments":false,"limit":1}
```

A second initial `query_tasks` call creates a new capture, even with the same arguments. To skip import observation explicitly:

```json
{"detailLevel":"summary","includeComments":false,"limit":1,"readPolicy":"cached"}
```

To continue a returned ordinary page:

```json
{"cursor":"the-returned-nextCursor"}
```

Continuation reuses the original records, complete metadata bytes and expiry. It does not recapture, wait for an import, extend retention or update freshness. An optional continuation policy must match the retained policy; malformed policy is rejected before lookup. A new request has its own diagnostic correlation even when capture metadata is reused. Ordinary pages retain their five-minute/eight-snapshot/16-MiB limits. Reusable portfolio views have their separately advertised scope and retention contract; a shared capture retains the same identity and freshness evidence.

A cursor retry requests the same frozen capture. If a caller needs newer data, start a new initial query. Expired/unavailable cursors require a new query; incompatible snapshot scope requires a compatible selector/view rather than treating an incomplete view as complete.

## Errors and retries

Read failures set the original `isError` and preserve their error payload. Metadata contains request correlation, category and policy/budget, without invented successful `asOf` or `snapshotId`. The structured presentation also reports its supplemental category.

| Failure | Tool error code | Read metadata category | Structured presentation category |
| --- | --- | --- | --- |
| Required storage failure | `QUERY_FAILED` for query_tasks; `READ_FAILED` for get_projects/query_milestones | `storage_failure` | `storage_failure` |
| Required serialization failure | Same tool mapping | `serialization_failure` | `serialization_failure` |
| Capture cannot be proved coherent | Same tool mapping | `incoherent_capture` | `incoherent_capture` |
| Total read deadline | `READ_TIMEOUT` | `READ_TIMEOUT` | `deadline_exceeded` |
| Admission/publication busy | `READ_BUSY` | `READ_BUSY` | `admission_busy` |

Input, selector, cursor and capacity errors retain their specific advertised codes and precedence. Successful local reads with stale/unknown freshness are not storage failures.

There is no automatic retry. After `READ_BUSY` or `READ_TIMEOUT`, apply backoff before a bounded explicit retry; an immediate retry can still encounter unfinished physical work. Set a maximum attempt count appropriate to the caller and stop/report failure after that limit. Correct invalid input rather than repeating it. Reduce scope/comments or wait for retention expiry on capacity errors. Never retry a protected write as a fresh read or discard its existing receipt/revision safety requirements.

## Diagnostics and validation

The bounded diagnostic sink emits measured queue, refresh, capture, transform and serialization intervals, terminal outcomes and physical finish/discard with the original operation correlation and deadline. Historical aggregate tests also measure aggregation; production rejects JSON-RPC wire arrays. Excess log records are dropped rather than delaying a timeout. Use these measurements to investigate slow stages; unexplained delay must not be attributed to CloudKit.

Executable caller tests cover initial capture versus frozen replay, active/inactive policy defaults, failure followed by explicit retry, backoff while physical capacity is retained, and advertised guidance. Fault tests cover catalog storage/serialization/incoherence codes and metadata. See the [bounded-read spec](../specs/bounded-read-freshness/requirements.md) and its acceptance handoffs for exact source pins and supported/unsupported platform evidence.
