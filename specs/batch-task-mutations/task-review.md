# T-2384 Task Plan Review

Status: tasks and conditional implementation approved by owner in parent at `Sentinel_edf7fd12288c819192ad45a04154372a` for plan `d592907`. Independent task1 may start; external delivery, ownership and test-slot gates remain.

Review [Rune task list](tasks.md), [approved design](design.md), [requirements](requirements.md), and [decision log](decision_log.md).

## Execution dependencies outside this Rune file

These are owner-controlled readiness conditions, not locally completable tasks. Rune blocked_by links describe the local DAG only; an apparently ready task must also satisfy these conditions.

- Task approval and conditional implementation authorisation were granted at Sentinel_edf7fd12288c819192ad45a04154372a. Start independent safety fixtures only until the remaining readiness conditions are satisfied.
- Before task 2 coordinator patch: agree write-coordinator ownership with parent/T63 and reconcile delivered shared changes. No independent shared edits; proposed patch is applied only by the owner or after explicit handoff. Task 1 can draft isolated fixtures without production changes.
- Before tasks 3–6 and 11–14 consume common interfaces: T63 shared handoff followed by T2383 delivery of approved immutable source/lossless JSON, encoder/full ready fallback, richer schema and provider seam. Require delivered T2383 task 15 (`gpzncvz`) commit/interface, including completed task 3 (`gpzncvn`, lossless source), 5 (`gpzncvp`, presentation), 7 (`gpzncvr`, complete bytes/fallback) and 9 (`gpzncvt`, output/schema). These are current draft Rune IDs, not delivery or task approvals. No guessed production interface, no duplication of serializer. T2383 validates this with a synthetic provider aggregate and has no dependency on production mutate_tasks or these final batch tests.
- Before tasks 13–14 shared wiring: T63 agreed integration ownership/handoff plus delivered common provider registration; one patch, no competing source edits.
- Before executing app tests: explicit implementation authorisation and T63 release of the heavy-test slot. Tests use isolated owning fixtures; no live guard store/recovery actions.
- Modern real-client activation remains T2383's explicit client-readiness prerequisite; tasks use automated capability fixtures without changing settings. No config/activation/deployment task is included here.

Sequence is T63 handoff → T2383 synthetic-tested common delivery → T2384 consumer/real registration. No reverse edge exists. One stream avoids conflicting coordinator/helper/integration ownership; seven adjacent RED/GREEN pairs add substantial behavior without trivial setup tasks.

## Verified external Rune references

Read-only sibling list: `/Users/arjen/Documents/Codex/2026-10-03/task-3/transit/specs/structured-mcp-results/tasks.md`.

| T2383 task | Stable ID | Required delivery |
| --- | --- | --- |
| 3 | gpzncvn | Owned lossless JSON documents/source factories |
| 5 | gpzncvp | Source-only presentation/provider selectors |
| 7 | gpzncvr | Complete result bytes/provider-owned mutation fallback; synthetic batch fixtures |
| 9 | gpzncvt | Output descriptor/schema providers |
| 15 | gpzncvz | Common source/schema/fallback plus modern dispatch integration after T63 handoff; delivered commit/interface is the consumer gate |

T2383 task 22 (`gpzncw6`) uses synthetic batch/current tool contracts and never waits for production mutate_tasks. Its covered-read task 17 is outside batch consumption. Cross-file prerequisites are recorded here rather than invalid foreign stable IDs in the local Rune blocked_by DAG. Reconcile references if sibling IDs change, and record the actual delivery commit before executing dependent consumers.

## Early risks

Saved-only observations and dirty coordinator routes are proved by tasks 1–2 before all later work. Complete fallback/resource behavior is proved by tasks 3–4 before execution and final integration. Failed safety fixtures block availability; flushing, rolling back UI edits or guessing an encoder is never a fallback.

## Coverage and required checks

| Approved criteria | Rune tasks |
| --- | --- |
| 1.1–1.4 | 5–8 and 13–14 |
| 1.5 | 1–2, 7–10 |
| 2.1–2.5 | 1–2 and 7–8; omitted-comment parity also 13–14 |
| 3.1–3.5 | 3–4 and 9–10 |
| 4.1–4.7 | 1–2, 5–6 and 9–10 |
| 5.1–5.6 | 3–4, 7–12 and 13–14 |
| 6.1–6.4 | Early fixtures plus 9–14 integration/regression fixtures |

Rune list rendered all 14 pending tasks without parsing warnings. One stream has one locally ready task and 13 blocked tasks; no work has started. Every GREEN is adjacent to and blocked by its RED. All dependency stable IDs resolve to earlier tasks, yielding an acyclic graph; both design risks block later consumers. Automated document checks cover all 32 requirement anchors and review links. No noncoding deployment/config/client activation tasks, decorative phases, independent parallel streams or orphan final components were added.

## Internal review synthesis

The local design critic reviewed first, followed by two independent internal peers focused on recovery/correctness and integration/maintainability under the documented fallback. No external model disclosure occurred.

| Reviewer | Findings and disposition |
| --- | --- |
| Critic | Narrow preview spies to new effect identities/timestamps, allowing saved UUID/date parsing. Separate post-await UI edits from impossible interleaving during clean synchronous phases. Name the external seam gates at their first consumer and correct MCP/Writes paths. All corrections adopted; final critic reports no blocker. |
| Recovery peer | Confirms 32-criterion coverage, early safe-context/fallback tests, historic replay/cancellation and isolated synthetic then real postcommit encoding tests. Stale design title/status metadata fixed; no substantive blocker. |
| Integration peer | Confirms incremental seven-pair plan, schema/domain boundary, one-stream ownership, early risks and noncircular external delivery. T2383 supplied current draft external Rune IDs, verified locally and recorded below; delivery remains a gate, no blocker. |

Consensus: plan is ready for its approval gate. No substantive reviewer divergence remains. What only implementation can establish—saved-only multi-context behavior, every dirty coordinator phase and complete fallback under encoder/resource faults—has explicit early RED/GREEN fixtures; a failed boundary blocks batch availability. External seam delivery, parent ownership/handoff, implementation authorisation and T63 test-slot release remain execution conditions, not assumed approvals. No app builds/tests, production source changes, guard changes or recovery actions were performed during planning.

## Approved task gate (historical request)

**Do the tasks look good?**

Parent routes this question to the user after required reviews. Task approval completes the spec plan; it does not silently authorise production implementation, shared-file handoff, heavy-test scheduling, settings, push, merge or deployment.

Owner approved the task plan and implementation once shared dependencies are ready at Sentinel_edf7fd12288c819192ad45a04154372a. This answers the gate; no further approval is requested for already authorised independent work.

## Actual external delivery consumed

Verified T2383 `DELIVERED15/gpzncvz` at handoff `b21e358c8a5ea1e287afe332c1fc50d83303ce19`, runtime source `543c4a757e4cb7f9f73c973d7cb1be5725c8f342`. All manifest source hashes match. Consumer dependency delivery is now satisfied; exact ten-file pure seam import `fe1c57f` preserves the coordinator/App/project/Makefile. Task3 resumes fixture preparation against real APIs. Later common16–22 are not reverse dependencies.

Before Task3 app-host RED, this older worktree still requires the parent-selected isolated foundation and containment-owned narrow App/project integration described in the delivered development-isolation component handoff. No runnable app command is claimed until signed isolated host preflight and exact suite inventory can be verified. Intended focused suites: `TransitTests/MCPBatchTaskEvidenceTests` and `TransitTests/MCPBatchTaskEncodingTests`. Request an exclusive slot only after that readiness exists. No old test-quick/production host fallback, client activation or live mutation is permitted.
