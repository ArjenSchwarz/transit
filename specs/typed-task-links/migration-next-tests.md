# Task1 remaining migration evidence and precise seams

Current contract: owner `Sentinel_c95239aefa6481919303c2353b8a9e9c` approved participating Transit writes with pre-save validation and outside-writer conflict reporting (decision_log.md ADR 4). The historical all-independent-writer/import validation-to-save fence and persistence-redesign completion gate below are superseded. Original tests, failures and approvals remain historical evidence; owned same-store domain/receipt saving and T-2402 deferral remain unchanged.

Deferred destination: **T-2402 — Set up isolated CloudKit integration testing**, created and freshly verified by the parent through the installed UI (Transit, Idea/Research). No duplicate live ticket write.

Current owner amendment `Sentinel_42e647a603ac81918cbb949ed1ca67bb` defers CloudKit test isolation/live verification to a separate ticket and authorizes proceeding without it. The historical external task2 blocker described below is superseded. Verified local migration/metadata GREEN can satisfy task2's remaining scope after review; no live smoke success is claimed. The next mandatory gate is task3/task4 atomic validation-to-save feasibility, with parent-scheduled execution and graph writes disabled until proven.

## Historical task2 GREEN queue — before owner deferral

This local queue now passed at immutable source aa5f56a7744c0dc8f09e974be8d9b8944982d822 in the parent-assigned slot. Fresh build/preflight, four distinct drained closed-store stages, both physical empty-table checks and all three expanded metadata/control cases pass. Evidence `/tmp/t1734-green.Zf1DYx`; detailed outcomes and retained hashes are in implementation.md. The slot is released after independent final drain. No repeat local run is needed without changed inputs or a new concern; the separate Development CloudKit completion gate remains outstanding.

The parent has now resolved all registration owners, including T-2384's final CoordinatorProbe list-only grant. The two model declarations and all seven current factories are being aligned on this isolated branch; the historical observations below describe the earlier RED source. Record the final clean HEAD and current source audit in the next run's evidence. Source registration readiness does not establish SwiftData macro compilation, inferred metadata or migration GREEN.

After a parent-assigned heavy slot, use a fresh private DerivedData/cache root and the locked-package, development-signing build-for-testing command in verification-readiness.md. Run `run_closed_store.py BUILD_PRODUCTS --run` directly: it performs the fresh signed-unit preflight and retains its base T1734Migration.xctestrun. Require seed, legacy, upgrade and reopen each to execute exactly one passing non-skipped case in distinct drained host processes; require preserved original raw fields/receipt bytes/physical multiplicity and zero physical rows in both new graph tables after upgrade and reopen.

Then use that preflighted base run file for the separate TaskLinkMigrationTests serial run with a fresh T1734Migration.xcresult path, without rerunning the output-exclusive preflight helper. Require both expanded entity metadata cases and the saved-field control to pass: real scalar types/defaults/optionality, no relationships and no uniqueness. Preserve source identity, logs, exits, per-case xcresults, preflight, manifests, store/WAL/SHM and physical graph counts. Sample an owned stalled host before bounded cleanup; stop on discovery, build, metadata, byte-preservation, migration or drain failure.

No heavy run is authorized merely by finishing source registration. Earlier offline runtime evidence predates the new model files and Makefile compile-list changes and cannot certify those changed inputs. The separate opt-in real Development CloudKit host/account/schema/deletion gate remains uncompiled and unexecuted; this local queue performs no CloudKit activation or publication. Even successful local GREEN leaves task2 incomplete and task3 blocked until the approved external gate is satisfied.

Source preparation `7c4b28944975f7b945cb3f45af53bd6ee2672334` follows the verified capability RED/control boundary at `4e44caa`. No new production declaration, shared registry, account operation or schema publication occurred. This document initially recorded task1 in progress. Subsequent critic-reviewed smoke source closes RED preparation; Rune now completes task1 and returns task2 next, with ownership coordination pending. All task2 completion gates below remain binding.

## Prepared local job (now executed through expected RED)

After the next parent-assigned heavy slot, build a fresh shared Transit Debug unit bundle using the locked-package, development-signing and private-cache command in `verification-readiness.md`. Skip the unchanged offline checks and dedicated smoke already verified at `237c7e1`. Do not run `prepare_unit_run.py` separately on the same products directory: the new runner invokes that signed-unit preflight itself and requires fresh outputs.

```sh
python3 tests/typed-task-links/run_closed_store.py BUILD_PRODUCTS --run
```

Replace BUILD_PRODUCTS with that fresh build's absolute `unit/Build/Products` path. The runner prepares allowlisted unit-only runs. Without `--run` it only preflights/prepares; it does not launch. Preparation consumes its fresh output paths, so use a different fresh build/output directory for an execution rather than invoking prepare then run on the same directory.

| Stage | Concrete assertion | Expected on current source |
| --- | --- | --- |
| seed | Six-entity CloudKit-none synthetic store; pre-save raw-field/receipt-byte manifest equals saved values | One passed case; process drains |
| legacy | A different drained host opens that existing six-entity store and matches original bytes/physical multiplicity | One passed case; genuine closed-store baseline control |
| upgrade | A third host opens with the **actual** default TestModelContainer schema; preserves old bytes and requires both link registrations | One failed case identifying missing entities; evidence retained; stop |
| reopen | A fourth host reopens successful upgraded schema, preserves bytes, and verifies zero physical graph rows | Not reached until the upgrade becomes GREEN |

Each stage requires exactly one executed, non-skipped case and a consistent xcresult/exit outcome. The runner checks both path aliases and the recorded stage host PID have exited before advancing; xcodebuild exit alone is insufficient. A bounded drain failure stops for parent sampling/cleanup; it does not delete stores or weaken the guard. Synthetic SQLite/WAL/SHM and manifests remain in the development app's private Data/tmp UUID directory. No live records are used. Build failure, missing observation, crash or zero discovery is not migration RED.

After a successful upgrade/reopen, read-only SQLite counts must show zero TaskLinkOccurrence and TaskLinkRemovalEvidence rows. This is physical local incidence evidence, not graph projection or CloudKit convergence. Unknown table layout fails closed for inspection.

## Source parity and static CloudKit compatibility

`python3 tests/typed-task-links/audit_schema_sources.py --check` is source-only and currently exits 1. The inventory has 19 entries and identifies seven current factories needing task2 registrations: TransitApp, TestModelContainer, MCPWritePersistenceProbeTests and the four MCP write probes. Dynamic Probe.swift needs manual mode review: historical seed-old remains pre-receipt/pre-link. Development-isolation historical/control fixtures remain deliberately graph-free; ContainerFactory receives its caller's schema and adds no registration.

This is a token inventory, not inferred runtime schema proof. The existing parameterized metadata tests will inspect real entity scalar types, defaults/optionality and absence of unique constraints/relationships once the models are registered. Those assertions currently stop at the missing-entity requirement. No source result proves server record types exist.

## Exact paired GREEN and ownership boundary

No production API seam is needed to compile the prepared RED source: it obtains the actual schema from an owning TestModelContainer and names future entities as strings. New model declarations and registration belong to **task2**, not task1. T-1734 owns the two approved Models files; App/schema and central TestModelContainer integration require targeted coordination with the containment/T-63 owner, and MCP probe/Makefile lists require their foundation owner's handoff. Use an explicit verified compatible source checkpoint; preserve legacy controls and every unrelated shared change. This schema-only seam does not require unrelated graph query/write features to be implemented first, and does not justify importing all owner branches.

The prepared closed-store RED must run before claiming task1's local migration fixture is established. Substantive opt-in development platform-deletion source is now prepared and reviewed; its future-model compilation and cleared execution remain unverified. If completing that fixture requires typed production declarations, the parent must coordinate that minimal task2 seam at the approved Red/Green boundary at the reviewed RED/ GREEN boundary without treating task2 as complete or enabling dependent graph work. Even with local GREEN, task2 cannot pass its full gate until its separate development-schema evidence exists. Atomic-save and bounded-capture gates remain untouched.

## Genuine external development gate

TaskLinkDevelopmentSchemaPrecheckTests remains explicitly opt-in and **local only**. The substantive future typed smoke is now separately prepared in tests/typed-task-links/development-cloudkit; see its README and red-boundary-review.md. It never creates a CloudKit container or makes a request, and deliberately cannot certify the external gate. It is not a completed platform-deletion smoke fixture.

Real verification requires the task2 model declarations, a separately cleared signed development CloudKit host/operator fixture, the reserved development account/environment, verified additive server types/fields, and observed platform deletion behavior. Parent must clear that environment and its heavy slot. The existing isolated unit host intentionally has no CloudKit entitlement and cannot supply this evidence. No schema initialization, account/signing settings change, production promotion or ticket-store access is authorized here. Do not infer remote convergence from any local or development deletion observation.

## Actual boundary

At source `4ba0c6569ac914c91f9953e55ef832e247fd03f6`, the fresh build/preflight passed; seed and closed-store legacy stages passed in distinct drained host processes; upgrade failed only for missing link entities; final reopen was not executed. See implementation.md and `/tmp/t1734-closed.zwjNwD/preserved-evidence-sha256.json`. Next local runtime work follows the coordinated task2 model/registration seam, then successful upgrade/reopen and metadata assertions. This does not satisfy the separate external development gate.
