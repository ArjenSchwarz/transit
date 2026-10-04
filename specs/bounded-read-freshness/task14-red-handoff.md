# Task14 diagnostics and caller-contract RED

Meaningful runtime RED is verified at immutable source `ffde7266813f7a80c7efac7f1487a611b4d656d8`. Xcode 27 guarded build-for-testing, signed isolated development-host preflight and exact compiled inventory passed. Only the two approved suites ran, serially, on separately restricted unit-test launch configurations.

| Suite | Declarations | Expanded bodies | Passing bodies | Failing bodies | Assertion issues |
| --- | ---: | ---: | ---: | ---: | ---: |
| MCPReadDiagnosticsTests | 5 | 5 | 1 | 4 | 14 |
| MCPReadCallerContractTests | 5 | 8 | 7 | 1 | 19 |
| Total | 10 | 13 | 8 | 5 | 33 |

The four diagnostic failures expose the inactive queue/writer and missing measured phase, late completion and historical aggregation events. The description failure exposes missing policy, evidence, deadline and retry guidance. All assertions remain intact. The disabled-sink control and four caller declarations passed, including all four policy arguments, exact frozen capture metadata, explicit retry after one storage failure and backoff while timed-out physical work remains admitted. There are zero skipped bodies, global/unknown issues or finalized runtime warnings.

Both test processes exited 65 normally because these expectations fail; both result bundles finalized successfully. No sampling or cleanup signals were needed. The worker verified runner/host absence and released the exclusive slot before extraction. Main independently confirmed the exact build, inventory and test runner PIDs absent. All 102 critical source hashes and 22 earlier artifacts remained unchanged.

The original build at `4cde372` and its first support-import retry at `9bc312e` both exited 65 before preflight/tests. They establish no behavioral RED. Exact owner support imports, seven bounded detached waits through a synchronous helper and two equivalent explicit optional-closure initializations repaired fixture compilation without changing production or assertions. Their logs, results and correction provenance remain preserved separately.

Final evidence is `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/task14-red-ffde726/`: `manifest.json`, `counts.json`, `executed-inventory-verification.json`, finalized summaries/bundles, source verification, preflight, commands and final drain. Its artifact manifest covers 3,853 retained files. Earlier compile-only evidence remains in `task14-red-4cde372`.

Task14 is complete; Rune reports Task15 as the sole ready stream and Task16 blocked. Task15 must implement bounded asynchronous diagnostics and accurate caller-facing descriptions, retaining the original correlation/deadline, physical worker accounting and atomic publication engine. Serialization measurement must bracket the actual operation-aware final RPC encoder; payload construction alone is insufficient. Historical wire-array aggregation remains component coverage because modern production rejects arrays. No GREEN source implementation or further app run is included in this handoff.
