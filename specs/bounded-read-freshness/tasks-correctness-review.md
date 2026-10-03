# T-63 task-plan correctness review

Reviewed `tasks.md` against approved requirements/design, the decision log, and the actual local `starwave-tasks/SKILL.md`. This is planning review only; it does not approve tasks or authorize implementation.

## Verdict and checks

No task-plan blocker identified. The sixteen flat tasks form a coherent incremental implementation chain. Seven behavior-changing green tasks (3, 5, 7, 9, 11, 13, 15) each immediately follow their corresponding red test task and depend on it. Task 1 qualifies for the skill's types/interfaces exemption; task 16 is testing-only. No unnecessary setup/function/wiring fragmentation is present beyond the required red/green pairs.

`rune list specs/bounded-read-freshness/tasks.md` succeeded without parsing warnings: sixteen level-one tasks, streams 1/2, all dependency references resolved. The dependency graph is acyclic: every dependency points to an earlier task. Automated anchor comparison found all 29 acceptance criteria referenced, with no missing or nonexistent IDs. This is syntactic coverage; the behavioral details also cover the important cases below.

## Correctness coverage

- **Saved-only capture:** tasks 2–3 cover saved visibility, excluded pending edits, fenced selector resolution, relationship/physical identity, empty domain versus empty selection, unavailable/purged history, incomplete related evidence, canonical comment-covered r1, and fail-closed coherence. Their early live/store feasibility gate is explicit. Downstream capture/projection work depends on task 3.
- **Freshness:** tasks 4–5 cover positive applicability, queued observations, preserved successful import evidence, unrelated/failed/in-flight events, monotonic recency and inconsistent clocks, default/cached/inactive policy, remaining wait budget, and outcome precedence. These can proceed independently against injected contracts; task 10 joins verified capture and monitor work.
- **Deadline/physical bound:** tasks 6–7 include admission before fallback preparation, real router-return availability, blocked MainActor, large aggregate serialization, long IDs/body ceiling, notifications, eight lingering workers/ninth busy, stop/restart and generated single-winner/permit sequences. Publication/routing work explicitly waits for this early verification outcome.
- **Atomic publication:** tasks 8–9 cover pending plus visible capacity, stale CAS, pre-encoded rejection, same-store aggregate changes, child reservation transfer, validate-all-before-any-commit, one swap per store, collision/routing, exactly-once discard and absence of unpublished IDs in selected success bytes. These directly cover the design-review lost-update correction.
- **Frozen pages/compatibility:** tasks 10–13 cover existing selection/order/errors, unchanged text shapes, metadata identity and precision, no cursor refetch/refresh, canonical r1 preservation and no-comment summary parity, actual T2382 helper integration, read-only/mixed batch behavior, write/fallback/maintenance regressions.
- **Diagnostics/caller contract:** tasks 14–15 test slow logging and late correlation as executable code, validate caller examples and update code-level tool descriptions. The caller guide remains a stated ancillary delivery requirement, correctly outside the skill's coding-only checklist; it must still be delivered to satisfy requirement 6.1.

The three design risk entries map to tasks 2–3 (capture/import-history proof), 4–5 plus integration (event applicability), and 6–7 (transport scheduling/encoding). Dependent work is gated by their green verification outcomes. The second stream owns separate import-monitor code and test doubles, so parallel work is meaningful; heavy signed-store/build/simulator checks remain coordinated through the parent.

T-63/T2382 ownership is consistent throughout. Shared types and publication hooks can be delivered before the final integration task; task 13 explicitly waits for parent-delivered T2382 modules and task 12 cannot pass integrated acceptance on fixtures alone. No portfolio aggregation, separately owned reusable-store implementation, refresh force-pull, persisted schema change, merge, or deployment is introduced.

## Refinements for execution

These are test-case clarifications, not changes needed to the approved design or blockers to task approval:

1. In task 10, explicitly enumerate omitted cursor policy and explicitly matching cursor policy as successful replay cases alongside malformed/conflicting policy. Both must retain the same bytes and bypass new capture/wait.
2. In tasks 2–3, distinguish an unavailable live signed-store test environment from evidence that the history/import invariant holds. Record unavailable/unsupported evidence and exercise the documented `incoherent_capture`/unknown outcomes; do not count a skipped live test as positive verification. If actual signing/account access requires human setup, capture that concrete prerequisite before dependent testing rather than inventing it now.
3. In tasks 8–9, assert that aggregate reservation transfer changes ownership without changing the total charged capacity, then prove rollback restores the original charge exactly once. The existing details already require this behavior; make the assertion numerical in tests.
4. Preserve the requirement-1.6 stop interpretation from the approved design: stop invalidates terminal/publication state, while unfinished physical work remains charged until it actually completes. The task plan correctly prohibits generation changes from clearing physical counts.

The user task approval gate remains outstanding. No implementation, builds, external calls, or commits were performed in this review.
