# PR 254 native review corrections and verification

Verified application/test source: `bbe3a2560584f7fb822aa8006b20f08d22284ce4`, based on parent documentation checkpoint `ebd7330`. This is new evidence for the PR corrections; [final-handoff.md](final-handoff.md) remains the truthful historical verification at81f78e7. No source changed during the following runs. The final commit after this source only records this handoff.

## Narrow corrections

`TaskLinkNativeLabels` supplies wording relative to the selected endpoint:

| Stored kind | Outgoing | Incoming |
| --- | --- | --- |
| dependency | Blocks | Blocked by |
| association | Relates to | Relates to |
| attribution | Introduced by | Introduces |
| duplicate | Duplicate of | Duplicated by |
| unrecognized raw kind | Unknown relation | Unknown relation |

Raw stored kinds and physical graph evidence remain unchanged. These are native presentation labels, not new MCP wire spellings.

`TaskLinksSection` keeps first/new-source loads immediate and debounces repeated same-source notification refreshes for100ms. Every save/import still invalidates; there is no task-specific notification filtering or neighbourhood-only capture. `TaskLinkNativeDetailState` invalidates its generation and clears the prior observation before waiting. It checks cancellation, selected source and generation after waiting **before** calling the provider, and again before publication. An already-canceled task cannot invalidate a current observation. The provider still reads the complete fresh saved graph with its original bounded budget and cancellation checkpoints. Navigation resolution, budgets, schemas, shared writes and CloudKit behavior are unchanged.

Existing eight native projection/navigation cases and assertions were preserved. New controls add ten direction-label contracts and two refresh lifecycle cases. The deterministic three-request burst supersedes one waiting capture, cancels another and proves exactly one provider reads the latest saved source plus unrelated cross-project task/link incidence; no old observation survives waiting. The canceled-before-start control proves the current selection/observation survives and no provider runs.

No capture speed benchmark or outside-writer fence is claimed. The improvement coalesces burst scheduling; each necessary capture still builds the complete graph. Optional per-graph encoder reuse and broader refactors were left out.

## Final native verification

| Run | Expanded outcomes | Declaration outcomes | Build/run and drain |
| --- | --- | --- | --- |
| Focused native | 20 pass,0 fail/skip | 7 pass | fresh build0/run0; host86721 drained |
| Full macOS units | 3,265 pass,0 fail,5 intentional opt-in skips | 2,530 pass,5 skip | exact focused products revalidated; run0; host86946 drained |
| Full iOS units | 1,403 pass,0 fail/skip | 1,326 pass | fresh build0/run0; host88774 drained |
| Full iOS UI | 26 pass,0 fail/skip | 23 pass | same fresh iOS products; run0; all27 recorded hosts drained |

Full-suite aggregate: **4,694 passed expanded executions**, five intentional macOS opt-in skips. All native summaries report zero runtime warnings. Compiled full inventories have no discovery errors: macOS2,535 declarations, iOS units1,326, UI23. The focused inventory explicitly enables7 declarations and filters the other2,528; it is not a full-target discovery claim.

`make lint` passed all ownership, source schema and development configuration guards, plus SwiftLint on652 files with zero violations. Log: `/tmp/t1734-pr254-native-lint.log`. Diff check passed. The fresh macOS build has the existing manual-target-order warning. The fresh iOS build has35 existing warning lines (manual target order, retroactive TaskStatus/TaskType Sendable conformances, unused values/results in existing tests); none points to the native correction files.

## Signing, isolation and artifacts

Full roots beneath `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/`:

- `t1734-pr254-native-focus.hnv9pd4u`: fresh `build.log`, `build-exit.txt`, compiled inventory, `summary.json`, `tests.json`, `run-outcome.json`, source pin and guarded runner/preflight source copies.
- `t1734-pr254-full-macos.k2h6pc3b`: `reused-build-proof.json` pins the exact successful unchanged focused build and drain; independent signed preflight and unfiltered runfile; compiled full inventory, `summary.json`, `tests.json`, `enumeration-outcome.json`, `run-outcome.json`, guarded runner/preflight source copies.
- `t1734-pr254-full-ios.1t0jwd2h`: `source-head.txt`, fresh `build-exit.json`/`build.log`, `signed-preflight.json`, per-target compiled inventories, `TransitTests-summary.json`/`TransitTests-tests.json`/`TransitTests-exit.json`, `TransitUITests-summary.json`/`TransitUITests-tests.json`/`TransitUITests-exit.json`, native xcresult bundles, guarded runner/preflight source copies, `process-census-timeouts.jsonl`, `final-recorded-pid-census.json`, `final-drain.json`, `owned-simulator-deletion.json`.

Preflight verified the exact signed `me.nore.ig.Transit.development` host, expected executable/test-host path and startup modes. macOS requires its development debugging entitlement and rejects CloudKit/push/AppGroup entitlements. iOS verifies simulator platform, exact development app/runner identity and strict signatures; app entitlements are empty. Unit and UI clones retain only their respective target, with unit-test/ui-test isolation modes and all inheritedT1734 opt-in flags sanitized. Packages and build roots are private/locked; no production store, account, live MCP mutation, schema promotion or settings change occurred.

The macOS full run reuses the successful **fresh** focused products only after exact source pin/build/run/drain and signature validation; no filter-only redundant build was performed. iOS had its own fresh build and separately enumerated full unit/UI targets. Deadlines stayed fixed: bounded build, enumeration, unit and1,200-second UI phases; elapsed process inspection time is charged to the original monotonic deadline.

Two transient first-attempt `/bin/ps` timeouts recovered through the next original bounded inspection. Their requested five-second timeout and actual elapsed durations are recorded; at most three attempts are allowed. Denial, nonzero output, malformed rows or an ownership mismatch remain fail closed. No runtime timeout or sampled teardown occurred. The final exact recorded-PID census proves all30 focused/full macOS/iOS runtime PIDs are absent.

Owned simulator `984525F2-7564-4EA6-903E-570A2D44A825` shut down and was deleted with exit0. Final census has no remaining owned simulator/app processes. No additional verification job remains active.

## Remaining ownership and limits

Development CloudKit setup/export/deletion and production schema promotion remain deferred toT-2402; these local corrections do not satisfy that future gate or activate a client. Actual UI execution here is iOS; macOS click/window resolution remains covered by its shared unit-tested resolver. The five macOS opt-in diagnostics remain intentionally disabled as documented in the historical handoff.

The parent owns review replies, PR body/checks, documentation/HTML archive, push and any eligible merge. This worker performed only local source/test corrections, isolated verification and the handoff commit; no push, main change, deployment or live task-record write.
