# Portfolio summaries: decision log

## Quick Decisions

| ID | Date | Decision | Rationale |
| --- | --- | --- | --- |
| Q1 | 2026-10-03 | Use full spec; feature name `portfolio-summaries`. | Explicit parent user approval: Sentinel_3ccdbb1152c88191b673f3dde9f76e60. |
| Q2 | 2026-10-03 | Prepare specs on dedicated `T-2382/portfolio-summaries` worktree based on `0db453b`. | User authorized isolation and commits; preserve T-2380 and other tasks. |
| Q3 | 2026-10-03 | Move T-2382 to spec after scope approval. | Local creating-spec workflow; confirmed committed Transit transition. |
| Q4 | 2026-10-03 | Preserve legacy activeTaskCount; add separate idea and in-progress counts. | Explicit user “Sounds good” to parent proposal, Sentinel_5479ed38c0cc8191a7c47a6487b6c0a1. In-progress count is the literal in-progress status; ready-for-review remains a separate bucket. |
| Q5 | 2026-10-03 | Retain actual five-second individual/read-only-batch response limit, with mixed-batch exception. | Parent reports user approved this response limit and explicitly instructed against adopting the proposed success-admission relaxation. Shared T-63 feasibility evaluation pending. |
| Q6 | 2026-10-03 | Approve the complete reviewed requirements and every remaining decision in the review. | Explicit user: “Both are approved for all decisions, including the ones in the requirements review” (Sentinel_fa39017e21a08191abdcd0b7ae6c9e8e). Design/tasks/implementation remain separate gates. |
| Q7 | 2026-10-03 | T-63 is sole writer of shared server/handler/schema registration; T-2382 supplies isolated summary/snapshot modules. | Parent coordination decision prevents concurrent conflicting shared-file edits; user design approval still required. |
| Q8 | 2026-10-03 | Reads return saved data only and exclude uncommitted UI edits. | Explicit user: “If something isn't saved, it shouldn't be returned” (Sentinel_bb00a4d9d8688191a33a0e6a34ea38db). This clarification applies to both tickets. |
| Q9 | 2026-10-03 | Align the isolated spec branch with merged T-2380 foundation `201205bd`. | Verified PR #249 merged at 201205bd4e786c7f152d8f99006b37da7da888c7. Its MCP tree matches inspected b618acf head; canonical main checkout and other worktrees remain untouched. |

## Approved requirements decisions

The following requirements proposals were approved together by Q6. Detailed implementation choices belong to the design gate.

| ID | Recommendation | Rationale / alternative |
| --- | --- | --- |
| P1 | Add workflow and nonterminal counts alongside approved idea/in-progress counts and all status buckets. | Makes every combined total explicit; these additional combined counts were approved in Q6. |
| P2 | Required timezone-qualified completion interval [start,end); current done and abandoned counts separate. | Existing completionDate records current terminal state, not event history. |
| P3 | Last recorded activity includes creation/status/comment/milestone evidence. | Uses existing timestamps; arbitrary edits cannot be claimed. |
| P4 | Retain views for five minutes with lifecycle invalidation and no silent eviction. | Matches T-2379 lifetime; cross-tool reuse itself is approved in Decision 1 below, but detailed lifetime/failure contract was approved in Q6. |
| P5 | Explicit orphan/invalid-link status buckets; collision diagnostics; duplicate UUID ambiguity fails summary. | Count physical records once without arbitrary attribution or silent deduplication. |
| P7 | Refresh-if-needed default, cached option, two-second wait and thirty-second import threshold. | Aligns T-63 recommendation; evidence never proves remote completeness. |
| P8 | At most ten deterministic identity samples per diagnostic category and scoped attribution-only failure. | Critic identified unbounded detail and unrelated-corruption failures; exact diagnostic counts remain complete. |
| P9 | Summary and snapshot-bound queries map unknown stored statuses to idea; ordinary queries retain stored-status filtering. | Technical peer verified MCPQueryFilters currently compares statusRawValue, unlike TransitTask.status fallback. Shared-view reconciliation requires one explicit rule without changing ordinary-query compatibility. |
| P10 | Reject incompatible/unsupported snapshot scope or options explicitly. | Architecture peer identified risk of silent live recapture or scope expansion defeating reuse. |
| P11 | Full/summary retained task details supported; comment bodies unsupported on reusable views. | User approved detailed task reconciliation, which needs captured descriptions/metadata; summary activity needs comment timestamps but not bodies. Unsupported body requests fail explicitly. |
| P13 | Preserve raw milestone status and expose effective open fallback with a warning. | Peer identified that model fallback alone could mislabel unknown raw status as recorded open. |

## Decision 1: Externally reusable captured views

**Date:** 2026-10-03

**Status:** Accepted — user Sentinel_5479ed38c0cc8191a7c47a6487b6c0a1.

### Context

The ticket requires counts that reconcile with equivalent queries at the same snapshot. Existing pagination retains encoded pages and cannot support new filters against a reusable captured task view.

### Decision

Allow summary and detailed task queries to use the same saved snapshot for real caller-visible reconciliation. T-63 owns the shared capture/freshness service supporting retained capture identity. T-2382 owns the externally reusable summary/task-query snapshot API and lifecycle, coordinated with T-63. Parent will assign shared handler/schema wiring ownership before design.

### Alternatives and consequences

An informational snapshot ID with internal tests only would cost less but would not permit callers to reconcile independently; the user approved real reuse. This expands query/API scope and requires retained immutable task data, filter semantics, capacity/lifecycle accounting, and compatibility tests. Five-minute expiry and detailed freshness policy were approved in Q6; the actual five-second response limit is approved.

## Coordination

## Decision 2: Reuse fenced committed-store capture

**Date:** 2026-10-03. **Status:** Accepted — parent user Sentinel_541ceb19e7c8819193d04d23c5263041.

T-63 supplies `captureScope: ReadCaptureScope` (`wholePortfolio`, `projects([LocalRecordKey])`, `selectedQuery` for ordinary narrow reads); completeness covers declared scope plus required identity/comment closure, and closure never grants broader reusable-query scope. T-63 supplies a fresh autosave-disabled SwiftData read context, value-only copy and before/after history/store/import-epoch fence; T-2382 consumes those values. This excludes unsaved edit forms without mutating the UI context. A prototype injected a saved transaction between project/task reads: the mixed values were rejected when history changed; a stable fresh context returned coherent new values. A UI-context transaction/save/rollback is rejected because it could commit or discard unrelated work. Unknown import/store association must remain unknown freshness; public evidence does not establish global convergence.

## Decision 3: Separate retained-view budget and explicit snapshot mode

**Date:** 2026-10-03. **Status:** Accepted — parent user Sentinel_541ceb19e7c8819193d04d23c5263041.

Use a new synchronized store with eight reusable views and 16 MiB charged encoded capture/page bytes, preserving the ordinary-page store's existing eight/16 MiB limits. This can retain up to 32 MiB of logical encoded data across both stores, plus object/transient overhead; it is not a heap cap. Combining stores would require reworking ordinary pagination and its compatibility/capacity semantics. Parent-approved single-writer integration routes explicit `snapshotId` queries to isolated T-2382 modules; ordinary filters/order/text remain unchanged. Retained full task detail includes canonical T-2380 revisions minted before comment stripping.

## Decision 4: Stage publication under independent completion arbitration

**Date:** 2026-10-03. **Status:** Accepted — parent user Sentinel_541ceb19e7c8819193d04d23c5263041.

No snapshot or cursor becomes visible until fully encoded success wins T-63's synchronized deadline/lifecycle gate. Coalesce selected batch changes into one candidate/version/reservation per store before entering the shared gate; validate all stores before any commit, and swap each store once. Retain displaced/discarded large bundles until after unlock so ARC destruction cannot block timeout arbitration. Timeout leaves physical admission charged until completion. Prototype measurements showed exact-boundary and coalesced timers can exceed five seconds; use a strict independent timer and internal response margin, and verify router/batch availability separately. A structured task-group race is rejected because group teardown waits for a noncooperative worker. Standalone counter/gate tests validate the mechanism but not app integration or real-time scheduling.

## Design quick decisions

| ID | Decision | Rationale |
| --- | --- | --- |
| D1 | One new tool `query_project_summaries`; replay `snapshotId` only; explicit snapshot `query_tasks` mode. | Exposes portfolio and scoped work without legacy payload changes or implicit live recapture. |
| D2 | Snapshot task filters are project UUID and effective status; full descriptions/metadata supported, comment bodies rejected. | Exactly supports approved reconciliation/detail scope without capturing an unbounded body API. |
| D3 | Accept zero to three fractional digits in window inputs and emit canonical UTC milliseconds. | Prevents normalized endpoints from losing comparison precision; parser/schema must declare restriction. |
| D4 | Use physical keys for attribution and UUIDs for public identities; deterministic bounded diagnostics. | Prevents display-ID/name collision deduplication and preserves corruption visibility. |

All design decisions above were approved unchanged by parent user Sentinel_541ceb19e7c8819193d04d23c5263041, including the final scoped-capture and aggregate publication amendments (T-2382 3932e88; T-63 5639c40). Task-list approval received in parent user Sentinel_c2e9343628948191b921868234aaf409; production implementation is authorized subject to foundation and integration gates.

T-2382 owns aggregation semantics and the dedicated summary service. T-63 owns read budgets and freshness. Parent coordinates shared snapshot capability and MCP handler/schema/read-only registration ownership before design/interface binding. No implementation has begun.

Scope/name approval does not approve requirements, design, tasks, or implementation. Requirements critic and peer review findings will be recorded with their disposition before the next approval request.

External Codex/Kiro CLI review startup was attempted after discovering installed binaries. Default sandbox initialization failed; initial escalated attempts were rejected for lacking disclosure authorization. Parent then supplied explicit user sharing approval Sentinel_7ba5dca061b4819183c1d6066aa1e949 and directed one retry. Both retries were rejected because automatic approval review did not recognize the delegated transcript as trusted direct user authorization. No further retry/workaround was attempted. The actual peer-review-validator instructions permit fallback; two independent subagent peers completed that path. Parent was notified of the exact remaining restriction.

The interim success-admission interpretation was not approved. Parent directed restoration of the actual five-second encoded-response/transport-availability guarantee and mixed-batch exception. T-63 supplied a source-backed independent timeout-coordinator hypothesis with bounded lingering work and late-publication gating, requiring a design prototype. The final requirements are aligned with that normative contract; no implementation was authorized.

## Implementation authorization

Parent user approved both task lists in Sentinel_c2e9343628948191b921868234aaf409. T-63 has the initial exclusive heavy build/test slot; T-2382 may prepare task1 interfaces and fixtures but cannot claim foundation verification or start dependent implementation before the foundation handoff passes. Use the repository’s Xcode27 toolchain throughout without downgrade; this is one execution constraint rather than a recurring product requirement. Commits are authorized; push, merge and deployment are not.


## Mechanical transport alignment — 2026-10-04

Parent explicitly confirmed that historical wire-batch wording is superseded by the user-approved latest-only, single-object POST contract; production JSON-RPC arrays must be rejected, while generic component aggregation tests remain. Requirements 7.1/7.5, design and tasks are mechanically aligned without a new product gate. Preserve application-level mutate_tasks receipts, individual read deadlines, all-store validation/rollback and outside-lock retirement. Historical component prototype results remain evidence, not production array support. Final modern/API15 acceptance is still pending through the T-63/T-2383 combined revision.

## 2026-10-04 — Sequential integration acceptance and delivery boundary

Earlier preparation/prototype/partial-run records remain historical evidence. Parent authorized sequential completion on the dedicated final-verification branch after T63 and T2383 finished, including local review, Pulsar publication and branch push. The finalized current 149-declaration / 221-body result and exact qualified 2,277-declaration / 2,581-body union are documented in integration-acceptance.md. T63 overlap, baseline warnings, original classifier failure and qualified iOS/UI reuse remain explicit. No gate was inferred from an unseen specification. External Claude disclosure approval is still required before PR/review workflow; actual installed-client validation is deferred post-merge to the user's MacBook.

## 2026-10-04 — Main reconciliation and publication approval

The parent forwarded explicit user approval for all pushes to the private Transit GitHub destination, sharing changes with the Claude reviewer, and overnight merges. That approval resolves the earlier publication/disclosure gates; their historical records remain unchanged. PR Pilot resumes against main `747983a7009d0015280f6e88ec811d933f4ef449`, with T2383 PR250 and T63 PR251 already merged. The unique delta is owned regression fixtures/tests, portfolio specifications and caller guidance, plus removal of the unused four-line scaffold enum; no new portfolio runtime behavior is manufactured. Foreign T63/T2383 documentation edits are preserved. The full reviewed branch is retained at `T-2382/reviewed-a4a60de`; original worktree dirt remains untouched.
