# T-63 — Bounded reads and explicit freshness

Review state: proposal; no requirements, design, tasks, or implementation approval recorded.

## Scope and workflow

Transit MCP reads can return an old local view without disclosing its limitations. The live ticket also records 30–50 second client timeouts whose cause remains unknown. This feature must bound completion across the whole server read path and expose honest local capture and import evidence.

The requested full spec workflow is appropriate: this changes a public MCP response contract used by other agents, and both the default refresh policy and compatibility envelope need user decisions. The approach to bounding synchronous SwiftData reads also needs design work. Proposed feature name: `bounded-read-freshness`; the review directory is provisional until the user accepts or overrides it.

## Evidence from this checkout

- Canonical repository: `/Users/arjen/projects/personal/transit`, origin `git@github.com:ArjenSchwarz/transit.git`.
- Base: `0db453bba3b1da3b8958723947dc41c165ecf0dd`; local main and origin/main agree. It contains merged T2379, bounded batch task queries.
- T2380: separate branch `T-2380/mcp-write-safety`, head `ef29b2baabbaa8a4886e63a03a267d6d7db86519`. T2379 is not an ancestor of that branch. This work does not change it.
- No repository AGENTS.md or .agents directory found. Repository CLAUDE.md and the actual local Transit, creating-spec, and requirements skills were read.
- `MCPToolHandler` is MainActor isolated. Task, milestone, and project fetches are synchronous; reads currently share UI services and context.
- `MCPTaskQuerySnapshotStore` retains serialized cursor pages, bounded by eight snapshots and 16 MiB. The 300-second snapshot expiry is a retention lifetime, not a response deadline.
- Cursor continuation returns the retained serialized page without a new store fetch. This behavior must preserve the original capture time and import evidence.
- `SyncManager.isCloudSyncActive` describes launch-fixed store sync mode; the preference may differ until restart. Freshness must use the active mode.
- Existing heartbeat writes do not establish that remote changes have arrived. No import tracking or documented force-pull facility was established in this scope inspection.

## Proposed requirements to develop after the first gate

1. Cover `query_tasks`, `query_milestones`, and `get_projects`, including single/batch task reads and cursor continuations. Agree whether optional maintenance reads belong in this change.
2. Bound read admission/queueing, store capture, optional import wait, transformation, and response serialization under one elapsed-time budget; return a defined timeout if no result can be produced in time.
3. Preserve successful local results even when remote freshness is unknown, stale, or a refresh wait expires; disclose those states separately from storage failure.
4. Describe the immutable local view with `asOf`, a snapshot identity, active sync mode, nullable last successful import time, and the scope of that evidence.
5. Preserve the original metadata on all retained cursor pages. Do not relabel old pages after an import or a later page request.
6. When active sync is disabled, skip import waiting and retain existing local data semantics. Additive metadata remains a proposed compatibility change for approval.
7. Preserve write behavior and existing explicit store failure results. Do not turn a failing fetch into an empty success.
8. Document retry behavior and exercise unknown/delayed/failed imports, inactive sync, slow/failing fetches, concurrent requests, and snapshot pagination.

## Decisions for the parent to surface

- Accept the full spec route and proposed name `bounded-read-freshness` (or provide another name).
- Compatibility: preserve current data payloads and attach additive metadata through MCP result metadata, or adopt versioned JSON envelopes? `query_tasks` already has an envelope; milestone/project responses are arrays.
- Default policy: recommend `refresh_if_needed`, with a recent-import threshold of 30 seconds and at most two seconds of freshness waiting; offer `cached` for callers that want immediate local evidence.
- Proposed total server budget: five seconds from decoded read admission to encoded result, including MainActor queueing. The network/client transport time is outside this server guarantee. This number is proposed, not approved or proven.
- Scope: defer a separate refresh MCP tool unless the user requires it. A per-read policy can provide a bounded refresh attempt without promising force-pull support.
- T2382 reconciliation: identical field names alone do not prove counts match across separately captured responses. Decide whether a summary and filtered query must share an addressable snapshot, or whether reconciliation is only defined within a shared capture.

## Technical risk for design

A timeout task on MainActor cannot run while a synchronous fetch blocks that actor. A structured task group can also wait for a non-cooperative operation even after cancellation. The design must show an independent response deadline, immutable Sendable capture boundaries, bounded pending work, and late-result disposal. It must not move live SwiftData models across actors, create an unlimited queue of abandoned fetches, or claim a stronger timeout guarantee than the runtime can support.

## Capabilities

The session uses workspace-write with automatic approval review. Supported per-command `require_escalated` was successfully used to create the dedicated branch/worktree because Git administration is outside the writable workspace. No permission settings were changed. Xcode 27.0 (27A266a) is installed; no Xcode MCP tools are exposed in this session. `/Users/arjen/bin/send-md-to-phone` is available and copies Markdown to `iphone181` through Tailscale; it does not generate web links. No heavy build or simulator work was run. No `memory_summary.md` was found in the local Codex file inventory.

## Approval sequence

The local creating-spec skill says each phase requires explicit approval. The requirements skill additionally requires the feature name answer before creating formal requirements. First surface the scope/name and behavioral choices above in the parent; then develop and review requirements. Stop again for requirements approval before design, design approval before tasks, and tasks approval before implementation. Keep the ticket at its observed `idea` state until the scope approval is recorded.

Implementation and pre-push-review, including its Pulsar step, are later phases. Coordinate shared MCP wiring and any heavy tests through the parent. No merge or deployment is authorized.
