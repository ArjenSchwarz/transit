# T-1734 local implementation handoff

All 22 approved Rune tasks are locally complete. `rune next specs/typed-task-links/tasks.md --format json` reports all tasks complete. Application/test source verified by the final platform runs is `81f78e7687029895faef4e0d914882f403962f26`; subsequent changes only record completion/evidence. Publication and main integration remain with the parent, outside this local implementation handoff.

## Final base and preservation

The typed branch is `T-1734/typed-task-links-final`, based on landed `origin/main` `e04c1268ee37bd4ae925d4d686954cf2121005c7`. Original worktrees/checkpoints remain preserved. Old `7d7271f0c86ed337ae52b0cb49fc152fea8f6a47` is retained by `T-1734/pre-landed-foundation-20261005`; the reconciled `9c8695e0070666b0902434c26b449881ba8d3023` had identical code/tests/Makefile and only three already-merged batch review documents differed. See [task14-checkpoint.md](task14-checkpoint.md). Canonical/main and canonical `.kiro` were untouched by T-1734; canonical/main is now e04, advanced outside this isolated work.

## Implemented acceptance scope

| Task pair | Local capability and executed coverage |
| --- | --- |
| 1–2 | Immutable scalar link/removal models; seven current schema factories; real process-separated six-entity seed/control → actual eight-entity upgrade/reopen; raw fields and receipt preservation. |
| 3–4 | Participating shared coordinator phase and opt-in owned same-store services; exact receipt binding/refetch/recovery; draft, save, encoding and replay boundaries. Existing baseline controls passed without inventing a cache defect. |
| 5–6 | Physical graph multiplicity, raw diagnostics, directed dependency SCCs, direct blocker assessment, complete proposed-plan validation and exact repair recognition. |
| 7–8 | Frozen saved graph closure, original read deadline, physical-slot/history fencing, populated index/result capacity accounting and no partial or late publication. |
| 9–10 | Explicit task-links-v1 r1 coverage, physical incidence canonicalization, empty-incidence transition, legacy missing coverage and unchanged historical receipt bytes. |
| 11–12 | Closed standalone wire deltas/preconditions, exact l1 selector, bounded public types and batch rejection; shipped batch tool name is `mutate_tasks`. |
| 13–14 | Final create UUID, saved endpoint/source checks, graph application after source precondition, one owned domain/evidence/receipt save, mixed changes, repair/no-op/replay and rollback. |
| 15–16 | Graph filtering before order/page/body selection; saved-only frozen results/cursors, current modern adapter parity and compatibility error surfaces without returning injected live values. |
| 17–18 | Bounded seven-day evidence cleanup with physical identity/fingerprint/date guards and owned rollback; active links and receipts are preserved. |
| 19–20 | Saved native relationship labels/diagnostics/blockers; unique saved UUID resolver at click and macOS window; cancellation/stale continuation/pending deletion controls; actual iOS relationship navigation and ambiguity UI tests. |
| 21–22 | Integrated real-handler/store/foundation regressions, final schema/contracts audit, full macOS/iOS unit and iOS UI verification. |

The 39 acceptance criteria remain mapped to these task pairs in [tasks.md](tasks.md), with requirements and design references preserved. Historical behavioral RED and compile-only failures remain distinct in [implementation.md](implementation.md), [task4-checkpoint.md](task4-checkpoint.md), and [task20-checkpoint.md](task20-checkpoint.md).

## Final verification

| Run | Expanded cases | Native declarations | Build / run | Runtime warnings |
| --- | --- | --- | --- | --- |
| Focused query/capture/wire compatibility | 170 pass, 0 fail/skip | 123 pass | 0 / 0 | 0 |
| Full macOS units | 3,253 pass, 0 fail, 5 intentionally disabled | 2,527 pass, 5 skip | 0 / 0 | 0 |
| Full iOS simulator units | 1,391 pass, 0 fail/skip | 1,323 pass | 0 / 0 | 0 |
| Full iOS simulator UI | 26 pass, 0 fail/skip | 23 pass | reused successful unchanged build / 0 | 0 |

Native flat compiled inventories have no discovery errors: macOS 2,532 declarations, iOS units 1,323 and UI 23. Expanded counts come from device/configuration summaries and retained native trees, not declaration totals. Full UI includes both relationship cases and the existing launch configurations.

`make lint` passed all ownership/create-schema/development-configuration guards and SwiftLint on 649 files with zero violations. Log: `/tmp/t1734-lint-81f78e7.log`. The final schema source audit passed all current registration paths, preserving intentionally graph-free historical controls. Its JSON is in the final macOS root below. Diff check passed.

The macOS build has one existing manual-target-order warning. The iOS build has 35 warning lines covering that warning, existing retroactive TaskStatus/TaskType Sendable conformances and unused values/results in existing tests. The build log retains exact locations; no platform runtime warning was reported.

### Evidence roots

All paths below are beneath `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/`:

- `t1734-query-compatibility-precedence.djxb5ue3`: `build.log`, `build-exit.txt`, `compiled-inventory.json`, `summary.json`, `tests.json`, `run-outcome.json`; host 69050 drained.
- `t1734-final-macos-corrected.7su76bgk`: build/enumeration/run command and exit files, `compiled-inventory.json`, `summary.json`, `tests.json`, `run-outcome.json`, `schema-audit.json`; runtime host 69279 drained naturally.
- `t1734-final-ios.ce22wn5q`: `signed-preflight.json`, `build-exit.json`, `build.log`, `TransitTests-compiled-inventory.json`, `TransitTests-summary.json`, `TransitTests-tests.json`, `TransitTests-exit.json`, `final-drain.json`, `owned-simulator-deletion.json`; unit host 71262 drained naturally. Owned simulator F16FC947-B7C9-4F00-A29A-D1744C20F8D4 shut down/deleted with exit 0 and no remaining owned processes.
- `t1734-final-ios-ui-bounded-census.r9nkfxdw`: unchanged-build proof, signed preflight, UI compiled inventory, `TransitUITests-summary.json`, `TransitUITests-tests.json`, `TransitUITests-exit.json`, `process-census-timeouts.jsonl`, `final-drain.json`, `owned-simulator-deletion.json`. All 27 recorded runtime hosts drained naturally, no timeout or sampled teardown. `final-recorded-pid-census.json` additionally proves all 29 recorded final macOS/iOS runtime PIDs are absent. Owned simulator 7A071F23-6A83-41A9-850F-8EF6B4DE983E shut down/deleted with exit 0 and no remaining owned processes.

### Preserved corrective evidence

The first final macOS pin cf33cb25 had 14 failures: eight query fixtures had only unsaved/mock seeds, five discarded injected storage-error hooks were lost, and graph's second task fetch erased injected malformed canonical data before selected serialization. Fixes explicitly inserted/saved only the read-fixture paths, restored error hooks while discarding successful live values, and reused the complete already-fetched saved task population within the capture fence. Assertions, budgets, dirty-write helpers and saved-only policy were preserved. A further selector-shape extraction and three controls preserve invalid/blank project validation before failing hooks. Final focused and full suites passed these corrections.

Two UI attempts stopped on a bounded process-census timeout rather than a test assertion: `t1734-final-ios.ce22wn5q` stopped during UI enumeration, and `t1734-final-ios-ui-retry.0daqwdp6` stopped during runtime. Both owned simulators were verified drained and deleted. Their partial logs/results are retained and are not full-UI success evidence. The final runner retries only transient `TimeoutExpired` inspection up to three five-second attempts; denial, nonzero/malformed output and PID ownership mismatch remain fail closed. Four first-attempt timeouts recovered in the final run, each logged; elapsed time remains charged to the original absolute 1,200-second runtime deadline. No source, assertion, setting or unit-run changes were needed.

## Practical limits and next ownership

- Development CloudKit setup, export and platform deletion verification are explicitly deferred to T-2402. No account/container/schema activity occurred.
- Atomicity is the approved participating local owned-save contract. Independent containers/importers can race; no global CloudKit or all-writer fence is claimed. Primitive counterexamples remain evidence of those particular primitives, not proof that all mechanisms are impossible.
- Native macOS click/window resolution is implemented and unit tested through the shared resolver. Actual native UI execution here is iOS; no macOS window UI execution is claimed.
- Five opt-in macOS cases remain intentionally disabled: the two primitive diagnostics, closed-store stage, development schema precheck, and outside-writer observation. Their earlier targeted evidence or explicit deferral is preserved.
- No push, PR, main merge, deployment, client activation or external source disclosure was performed. The parent owns final review/CHANGELOG/overview/archive and any separately authorized publication.
