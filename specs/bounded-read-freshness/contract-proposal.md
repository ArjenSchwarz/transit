# Shared read contract proposal — T-63 and T2382

Status: draft for parent and user review. The user approved preserving existing payloads with additive metadata, refresh_if_needed default, five-second total/two-second refresh limits, the mixed-batch delivery exception, same-snapshot summary/task-query reuse, and deferring a separate refresh tool and maintenance reads. The parent assigned T2382 external snapshot API/lifecycle and T-63 compatible shared capture/freshness. Remaining fields, 30-second import threshold, admission bounds, and exact schema/integration are not approved requirements or design.

## Meaning of a captured view

`asOf` is the UTC timestamp assigned when local immutable data capture completes. It describes the data returned, not the most recent server response, latest remote write, or global CloudKit convergence. `snapshotId` is an opaque identity for that captured view; equal timestamps do not establish equal snapshots.

Every page of a captured result keeps exactly the same `asOf`, `snapshotId`, and freshness evidence. A cursor continuation may have a new request latency or response time, but these do not replace the captured metadata. Snapshot retention expiry stays distinct from the per-request read deadline.

## Proposed logical shape

```json
{
  "asOf": "2026-10-03T15:00:00.000Z",
  "snapshotId": "opaque-view-id",
  "freshness": {
    "syncState": "active",
    "assessment": "recent_import",
    "assessedAt": "2026-10-03T15:00:00.000Z",
    "lastImportedAt": "2026-10-03T14:59:55.000Z",
    "evidence": "local_import_observation",
    "recentImportThresholdMs": 30000
  },
  "read": {
    "policy": "refresh_if_needed",
    "refreshOutcome": "recent_import",
    "budgetMs": 5000
  }
}
```

This shape is logical metadata. Placement in existing array responses versus query envelopes is an open compatibility decision; do not change shared schemas before that decision is approved.

| Field/state | Meaning |
| --- | --- |
| `syncState: active` | The running store was configured with CloudKit. |
| `syncState: inactive` | The running store has no CloudKit sync; no import wait applies. |
| `lastImportedAt: null` | No successful, relevant import is known; never substitute heartbeat or response time. |
| `assessment: recent_import` | A successfully observed relevant import ended within the disclosed threshold before capture; it is not proof all remote changes are visible. |
| `assessment: stale` | Last known successful import is older than the disclosed threshold. |
| `assessment: unknown` | No trustworthy relevant import evidence exists, including observer unavailability or process-start uncertainty. |
| `assessment: not_applicable` | Cloud sync is inactive; the data is a local view. |
| `evidence: local_import_observation` | The endpoint observed a relevant completed successful import, subject to verification that the evidence applies to the captured context. |
| `evidence: none` | No trustworthy import evidence. |

Use UTC ISO 8601 with a documented precision for wire dates, and a monotonic clock for durations/deadlines. Freshness age is assessed once at capture; retained pages do not gain newer import evidence. A caller can compute the view's current age from fixed dates. A later failed import must not erase the last successful timestamp or turn the captured view into a fresh one.

## Policy, deadlines, and errors

`cached` captures the local view without import waiting. It does not mean bypassing the local store, and still has a fetch/encoding deadline. `refresh_if_needed` skips waiting if evidence meets the configured recency threshold; otherwise it attempts or observes refresh activity within the remaining total budget. Absence of a supported trigger yields `unavailable` only when there is also no relevant import already in flight. An existing relevant import can instead complete, fail, or time out during the bounded observation interval.

Proposed refresh outcomes: `not_requested`, `recent_import`, `import_observed`, `timeout`, `unavailable`, `failed`. These describe refresh handling separately from freshness assessment and local fetch success. An observed failed import can coexist with valid cached data and a prior successful import timestamp. No outcome claims guaranteed CloudKit force-pull.

Approved limits are a five-second total server read budget and at most two seconds of import waiting. A 30-second recent-import threshold remains proposed. Admission queueing, capture, transformation, and serialization share one deadline; the refresh wait is not extra time on top of it. Individual/read-only batch responses have that deadline; mixed batches produce read results within it but may await write completion for combined delivery, as the user approved.

If the deadline leaves no usable captured result, return a machine-readable `READ_TIMEOUT`, indicating the exhausted phase when known. A fetch or encode failure returns `READ_FAILED` with a stable failure category, or the existing tool error code if compatibility requires it. Keep validation/cursor/capacity errors distinct. Never return empty results to disguise failure. Both names remain proposals until the error compatibility decision is made.

Retries start a new bounded read and a new capture, except cursor retries replay the same retained page until its existing expiry. A refresh timeout does not warrant an automatic unbounded retry loop. Explicitly document a caller backoff recommendation and admission limits during design.

## T2382 integration boundary

Portfolio totals and milestone breakdowns must be derived from one coherent immutable capture and carry this same metadata. Import evidence applies only after the completed import is visible to that selected view. T-63 owns the shared deadline, policy, and import-evidence service proposal; T2382 owns summary aggregation and identity/status semantics. Parent coordinates MCPToolHandler, MCPToolDefinitions, server deadline wiring, and any cross-ticket snapshot storage changes.

Two independent captures cannot be promised to reconcile merely because both say `asOf`. T2382's approved same-snapshot behavior needs a shared retained view supporting both summaries and filtered queries. Existing task cursors remain opaque page tokens, not automatically general-purpose snapshot selectors; the reusable snapshot selector is T2382's API/lifecycle scope.

The user approved summary and detailed task queries using the same saved snapshot. The parent assigned T2382 the externally reusable summary/task-query snapshot API and lifecycle; T-63 shared capture/freshness must preserve retained capture identity. When that mechanism reuses a view, summary and query preserve its identity, capture time, and import evidence. Exact API/storage integration remains a design gate.

## Verification needed in the design phase

- Confirm the import event source actually represents the SwiftData store and context used to capture reads, including unfocused/headless execution, failures, and multiple store events.
- Establish what supported refresh trigger exists, if any. Preserve an honest unavailable path.
- Prove a slow synchronous MainActor fetch does not prevent deadline response, and bound lingering work after timeout.
- Decide whether preserving the shared UI context is essential to read-your-local-writes behavior before considering an isolated read context.
- Preserve exact original metadata in serialized cursor pages and validate summary/query reconciliation using an identical snapshot.
