# MCP portfolio summaries

`query_project_summaries` reports recorded saved-local workload. It uses the [modern single-object request/result contract](mcp-result-contract.md) and [bounded read/freshness contract](mcp-read-contract.md). Counts do not establish product, release or milestone readiness.

## Requests

For a new portfolio summary, supply these `tools/call` arguments:

```json
{"start":"2026-10-01T00:00:00Z","end":"2026-10-04T00:00:00Z","limit":100}
```

`limit` is an integer from 1 through 100. Omit selectors for the whole portfolio, or add exactly one of `projectId` (UUID) and `project` (name). Unknown, ambiguous, malformed or conflicting selectors fail explicitly. `readPolicy` may be `cached` or `refresh_if_needed`; the latter is the default.

`start` and `end` require explicit timezone offsets, seconds, and zero to three fractional digits. Date-only values, missing endpoints and `start >= end` are invalid. Results echo UTC endpoints with millisecond precision. The interval includes start and excludes end.

Continue with only `cursor` and, optionally, the original `readPolicy`. Replay the first summary page with only `snapshotId`. Neither operation recaptures current records or extends expiry; lost/expired views require a new summary.

## Count definitions

Every project and milestone has all eight effective task status buckets, including zeros. Project totals reconcile with valid milestone totals, tasks without a milestone, and tasks with an invalid milestone association. Tasks with missing/unresolved projects are reported separately from project totals. Empty projects and milestones remain visible.

- `ideaCount` is the idea bucket.
- `inProgressCount` is only the in-progress bucket.
- `workflowTaskCount` is planning + spec + ready-for-implementation + in-progress + ready-for-review.
- `nonterminalTaskCount` is idea + workflow. Existing `get_projects.activeTaskCount` retains this nonterminal meaning, including ideas.

Unknown stored task statuses count as effective idea and are diagnosed. Ordinary `query_tasks` without a reusable snapshot retains its existing stored-status filtering, fields, order and frozen cursor behavior.

Recent done/abandoned counts include only currently terminal records whose recorded `completionDate` lies in the half-open interval. Missing terminal completion dates are counted explicitly but excluded from window counts. Restored nonterminal records are excluded even if they retain a completion date. These are current-record counts, not historical transition counts.

## Activity, milestones and diagnostics

`lastRecordedActivity` is the newest task creation/status-change, comment creation, or milestone creation/status-change timestamp, with evidence kind and identity. It is null when no evidence exists. Ties sort lexically by evidence kind, UUID, then physical identity. Arbitrary project/task edits without a recorded modification timestamp are excluded.

Milestones report their raw and effective recorded status, UUID and optional display ID. Unknown milestone status is diagnosed and interpreted as open; terminal tasks do not change milestone status. Invalid cross-project/unresolved milestone links are reported rather than credited to that milestone.

Names and display-ID collisions never merge records. Diagnostics contain exact affected-record counts, at most ten deterministic identity samples and `sampleComplete`. Permanent display-ID fields are null when unavailable. Relevant duplicate UUIDs cause explicit identity ambiguity; unrelated scoped corruption does not broaden or fail the selected project.

Summaries omit individual task descriptions, task metadata and comment bodies.

## Reconcile against the captured view

Use the returned `snapshotId` in `query_tasks`:

```json
{"snapshotId":"<returned-UUID>","detailLevel":"summary","includeComments":false,"limit":100,"projectId":"<project-UUID>","status":["in-progress"]}
```

Snapshot mode requires `snapshotId`, `detailLevel` (`summary` or `full`), `includeComments:false` and `limit` (1–100). Supported filters are project UUID and an array of effective statuses; an empty array is unrestricted and duplicates are deduplicated. Initial snapshot mode permits no readPolicy override. Other options, comment bodies and scope expansion fail explicitly. Full detail includes captured descriptions/metadata and canonical comment-covered revisions without loading live comments.

For the same project and effective-status filters, counts across all task pages equal the summary buckets. Later saved changes/deletions do not change this comparison. These status counts are distinct from completion-window and invalid-association breakdowns.

The view expires five minutes from its original creation. Capture time (`asOf`), freshness evidence time, completion interval and expiry describe different facts. Pages/replay preserve original counts, metadata and expiry; they do not claim all remote changes have arrived. Eight views and 16 MiB of logical encoded capture/page charges are retained separately from ordinary query pagination. This is not a total heap cap; live views are not silently evicted to make room.

## Bounded outcomes

Single-object summary reads make encoded success or typed failure available within the tested five-second admission budget. Timeout/capacity/read failure never returns partial counts as complete success and never publishes a late snapshot. `READ_TIMEOUT`/`READ_BUSY` require explicit backoff/retry; compatibility and invalid snapshot/cursor errors require correcting options or starting a new summary. Shared storage/coherence/serialization failure categories remain distinguishable from validation and valid empty results.

Production JSON-RPC arrays are rejected. Application `mutate_tasks` remains one mutating `tools/call`; its receipts are preserved and it has no read-only five-second guarantee. Installed-client compatibility is deferred to the user's post-merge MacBook check.
