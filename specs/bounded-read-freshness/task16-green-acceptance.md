# Task16 integrated acceptance

Source checkpoint: `dbf3355d66ab51767fc97ef840dac2ead9c3573b`. Production source remains exactly the verified cumulative T2383 `d86f3ad`; the successor to T63 integration `b8c8194` changes only four explicit detached-task priorities in one macOS test fixture. Assertions, deadlines, synchronization and production code are unchanged. All four local review agents inspected that repair and found no issue.

## Finalized native coverage

Twenty-three selected finalized native result bundles cover the full configured macOS unit inventory: **2,189 declarations exactly once and 2,425 expanded executions passing**. There are zero failures, skips, expected failures, runtime warnings or legacy global issues. The selection excludes every unfinalized attempt and the superseded individual publication-method runs. Native declaration IDs, rather than console totals alone, establish the disjoint exhaustive union.

Root independently queried each actual native summary, test tree and legacy issue object, then reconciled the union to the compiled full inventory. Root also rehashed 704 earlier bounded-attempt artifacts, 5,626 successor artifacts and all 537 current source inputs. Evidence is outside Git under `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/task16-publication-qos-dbf3355/`: `manifest.json`, `coverage-union.json`, `global-issues-verification.json` and `artifact-sha256.json`. Independent review is in the sibling `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/root-final-verification/` directory: `native-final-review.json` and `hash-final-review.json`.

The successor packet's copied source hash table has correct current row hashes but retains two predecessor labels at its top. Root preserves those indexed bytes and supplies the explicit corrected successor pin in `root-final-verification/source-sha256-dbf3355.json`; no source mismatch was found.

## Preserved limitations and repair

Five attempts passed their bodies but failed native finalization: the original 2,171-declaration remainder, Chunk04, its third subgroup, the isolated publication suite, and one isolated publication method. Their samples, actual termination outcomes and unfinalized bundles remain preserved and excluded from acceptance. Scoped termination followed bounded post-body waits and exact owned-process verification. The root cause of the native finalization stalls remains unproved.

Individual isolation exposed two actual Thread Performance Checker priority inversions: a user-initiated semaphore waiter depended on a default-priority detached finalizer. The adjacent fixture repair sets four producer/gate task priorities explicitly to `userInitiated`. A new isolated signed build and all 11 publication declarations finalized normally, with the checker enabled and no warning messages. This verifies the repaired fixture; it does not retroactively establish the cause of earlier stalls.

Chunk05 began while Chunk04 was still waiting after its test bodies. Chunk05 itself finalized normally and contributes 300 declarations/387 executions, but retains that post-body overlap qualification. The worker subsequently enforced a fail-closed zero-owned-runner/host check before every inventory and runtime launch, and all remaining launches were serial with normal drain. No cosmetic rerun erases the sequencing deviation.

The new build's first invocation failed before compilation because its private temporary directory was absent. Its log and exit74 are preserved separately; directory preparation was corrected, and the successor build passed. This is not a test result. Strict signed development-host preflight passed with unit mode, exact host startup guards and no CloudKit, push or app-group entitlements. Full lint passed 532 files with zero violations. All owned heavy jobs are drained and the slot is released.

## Platform qualification and remaining workflow

Finalized iOS results (1,310 declarations/1,358 executions) and separate UI results (21/24) are reused from the actual T2383 tested artifact at `6bc20e16bd29137526d5f4a804e7c84829e6e073`. Root verified that all 20 changed Swift files are entirely macOS gated in both versions and that active iOS/build/configuration inputs are unchanged. The updated proof is `task16-reused-ios-evidence/source-equivalence-dbf3355.json`. This is qualified reuse, not new iOS execution or macOS evidence.

Task16 is complete. Live signed-store import applicability remains unsupported/unproved; approved `unknown`/null/`unavailable` behavior remains binding. T2383 installed-client compatibility is separately owner-deferred. No client activation, live-data repair, CloudKit operation or deployment occurs.

Full pre-push review and Pulsar publication completed before the original branch push. Parent subsequently forwarded explicit approval for pushes and external Claude sharing. Reconciliation on squash-merged main preserves all 537 compiled inputs byte-for-byte and all previous qualifications; the remaining unique tests/docs proceed through the updated scoped review and PR Pilot.
