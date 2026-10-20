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

History-before; isolated context creation; project fetch/validation; milestone fetch/validation; task fetch; graph; selection; scoped comment fetch; comment index/value materialization; ordinary record copies; consolidation evidence; history-after; final capture validation. Completed events retain original operation correlation and measured monotonic intervals. An active stage becomes the scalar failure phase even if the stage blocks past the deadline. Outside measured stages restore the generic capture phase. Do not fabricate a completed duration for a stage that has not returned.

No payload, error descriptions, store paths, selector values, task/project IDs, names, descriptions, comments or metadata are added to diagnostics. Existing operation UUID correlation stays in debug logs only; failure journal remains content-free and bounded.

## Validation plan

- RED/GREEN: an actual builder-backed full-read fixture must report ordered internal stages with original correlation and success, preserving the ordinary read result.
- Throwing and blocked-stage fixtures must retain failure attribution and physical ownership, then record completion only when work physically returns; a discarded late result must not become success at the wire.
- Existing diagnostic-sink boundedness, privacy schema, failure journal, capture builder/scope/comment tests and coordinator contracts remain green.
- Run focused macOS tests and lint; no broad UI reruns. Use only isolated synthetic in-memory, CloudKit-disabled fixtures.
- At most one bounded representative live read with existing scalar diagnostics, no restart/deployment/settings writes. The running app cannot emit newly added stages until an explicitly reviewed deployment; do not represent synthetic timings as live attribution.

## Implementation and evidence

RED confirmed: the builder-backed internal-stage assertion fails because no internal stages are emitted; the other five diagnostic tests pass. `make lint` passed with zero violations. This checkpoint intentionally retains that failing regression before implementation.


## Live observation — 20 October 2026 11:57:55 UTC

Exactly one bounded cached full read (one existing task, comments omitted from payload) completed successfully in 2.5153 seconds. PID1953 remained the original process at 4 days 12 hours 32 minutes uptime. Existing scalar logs measured queue 4.177ms plus actor queue 0.159ms, refresh 1.373ms, capture 2355.691ms, transform 46.105ms and serialization 0.216ms. Terminal success was selected 2441.213ms after admission and physicalFinish reported zero workers immediately afterward. Failure journal remained at 34 records. No timeout or post-timeout stack sample occurred in this run.

Capture dominated this successful read, but the installed binary cannot emit the new internal stages. This observation does not locate its internal slow operation or establish uptime, actor contention or sync as cause. It does demonstrate actual worker recovery. The new diagnostics require a separately reviewed deployment before live internal attribution is possible. Replacing the running app would require a controlled lifecycle change and lose the current uptime observation; no deployment or restart was performed. Raw live responses were not saved or uploaded; local supporting receipts contain only scalar diagnostics.

## Scope and safety review

Thirteen fixed stage labels reuse the existing bounded sink; no new logger, private values, error formatting, database writes, settings, clocks/deadlines, schema migration or early permit release. The read request retains scalar diagnostic operation correlation only during capture, not in the frozen view. Disabled diagnostics bypass measurement. The journal accepts only the typed phase enum, including the new stages, while rejecting arbitrary text. Existing success/debug event dropping and priority failure journaling remain bounded.

The entity fetch helper moved to a small extension to keep the builder within repository lint limits. The capture sequence remains linear so its history fences and ordering are directly reviewable. A targeted function-length exemption documents instrumentation wrappers in that sequence.

## Interpreting the diagnostics

Stream category `MCP.Read` at debug level for the relevant process. Existing `read id=...` correlation joins completed stage intervals, capture totals, terminal selection and physicalFinish. `elapsed_ms` is a completed stage duration; `admission_offset_ms` locates its start within the original request budget. A stage-level `success` describes that synchronous operation returning normally, including when its result was too late for RPC publication; use the separate terminal event to determine request success. There is no per-row logging or change to MCP result payloads.

If work blocks, the off-actor failure snapshot can name an active stage and its age before the stage completes. The completed event may arrive later or be dropped under existing bounded-sink pressure; an absent completed event is not proof of leaked work. Generic `capture` remains the phase between measured boundaries. History-before/after can return immediately in actor-only fixtures. Comment fetch/validation stages can return immediately when a request needs no corresponding values; their intervals include that decision rather than inventing a database fetch.

Thirteen stage events add scalar queue activity. The existing capacity of 64 is unchanged; overflow/drop accounting and priority failure retention remain important during concurrent requests. No additional retained payload or row buffers are introduced.

## Remaining limitation and next step

The diagnostic gap is addressed; the intermittent production slowdown itself is not claimed fixed. Keep the current live process intact. Review this feature branch, then arrange an explicitly approved instrumented deployment/lifecycle transition when the user is ready to end the current uptime observation. One representative read after deployment can locate the internal cost; preserve natural timeout evidence before considering another optimization. No broad UI, cloud, unrelated-project or authentication work is part of this follow-up.

## Final verification

- RED: the new builder-backed stage assertion failed before instrumentation; the five existing diagnostic tests passed.
- GREEN: 42 focused tests passed, zero failures/skips, across capture builder, scope, timing, validation, coordinator, diagnostics and failure-journal suites. The final source also passed all 10 diagnostic/timing tests after formatting/helper moves.
- Scoped-comment and comment-fetch failure regressions: 13 tests passed, zero failures/skips, including synthetic volume, duplicate physical/logical owners, saved history fences, orphan coverage and typed failure preservation. The earlier nonexistent generic comment-suite selector was corrected; only executed suites are counted here.
- `make lint`: all ownership/schema/development configuration preflights and SwiftLint passed, zero violations across 754 files. `git diff --check` passed.
- Added behavior tests cover original operation correlation, ordered stage intervals, throwing-fetch attribution without changed error semantics, timeout selection during a blocked fetch before physical completion, accepted fixed journal stage names with arbitrary private strings rejected, and unchanged saved canonical records/revisions.
- No full simulator/UI suite or live-cloud test was run: this is a macOS-only capture instrumentation follow-up, with focused validation requested and broad UI reruns excluded. Existing unrelated UI compiler warnings were not changed or suppressed.

Verification logs, result bundles, source manifest and scalar live receipts remain local to the delegated workspace. No raw live response or private store data is included in this branch.
