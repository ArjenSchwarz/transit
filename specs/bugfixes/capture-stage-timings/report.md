# T-2455 capture-stage timing follow-up

## Problem and authorized scope

Intermittent MCP read timeouts recur after the scoped comment-fetch fix. The same live process has recovered without restarting. The user approved capture-stage timing instrumentation on 20 October 2026; implementation follows that approval. This is a diagnostic follow-up, not a claimed fix for the remaining slowdown.

Expected: one bounded saved read reports which capture operation consumed time, without private content and without changing capture results, deadlines or worker ownership. Actual: existing capture timing is one coarse interval; timeout snapshots cannot distinguish store fetch, graph, comment materialization, record copying or consolidation/history work.

## Inspection and cause limits

1. `MCPReadService.capture` records refresh/capture/transform and passes a deadline budget into synchronous main-actor capture.
2. `MCPReadCaptureBuilder` performs persistent-history fences, project/entity fetches, graph capture, selection, comment fetch/index/copy, ordinary record copying, consolidation evidence and final validation synchronously.
3. `MCPReadCoordinator` can publish timeout while synchronous capture continues; physical ownership remains until worker completion. A terminal timeout must not release that permit early.
4. The bounded diagnostic sink queues immutable scalar events off the capture actor. Its failure journal validates an explicit phase allow-list; new stage phases must be admitted there too.
5. Prior live evidence located whole-store comment materialization (fixed by PR260). Later failures occurred in capture, queue and transform. Uptime correlation does not identify the remaining cause. No private store copy or live-cloud experiment is justified.

Why does the response time out? The request exceeds the internal 4.85-second selection cutoff. Why does capture consume that time? Some synchronous capture work or scheduling delay is slow. Why can it not yet be attributed? Existing diagnostics combine many operations into one capture phase. Further whys about database contention, sync or uptime remain unproven. The confirmed defect addressed here is missing internal attribution.

## Proposed diagnostic boundaries

History-before; project fetch/validation; milestone fetch/validation; task fetch; graph; selection; scoped comment fetch; comment index/value materialization; ordinary record copies; consolidation evidence; history-after; final capture validation. Completed events retain original operation correlation and measured monotonic intervals. An active stage becomes the scalar failure phase even if the stage blocks past the deadline. Outside measured stages restore the generic capture phase. Do not fabricate a completed duration for a stage that has not returned.

No payload, error descriptions, store paths, selector values, task/project IDs, names, descriptions, comments or metadata are added to diagnostics. Existing operation UUID correlation stays in debug logs only; failure journal remains content-free and bounded.

## Validation plan

- RED/GREEN: an actual builder-backed full-read fixture must report ordered internal stages with original correlation and success, preserving the ordinary read result.
- Throwing and blocked-stage fixtures must retain failure attribution and physical ownership, then record completion only when work physically returns; a discarded late result must not become success at the wire.
- Existing diagnostic-sink boundedness, privacy schema, failure journal, capture builder/scope/comment tests and coordinator contracts remain green.
- Run focused macOS tests and lint; no broad UI reruns. Use only isolated synthetic in-memory, CloudKit-disabled fixtures.
- At most one bounded representative live read with existing scalar diagnostics, no restart/deployment/settings writes. The running app cannot emit newly added stages until an explicitly reviewed deployment; do not represent synthetic timings as live attribution.

## Implementation and evidence

RED confirmed: the builder-backed internal-stage assertion fails because no internal stages are emitted; the other five diagnostic tests pass. `make lint` passed with zero violations. This checkpoint intentionally retains that failing regression before implementation.
