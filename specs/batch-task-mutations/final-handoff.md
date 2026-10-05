# T2384 publication handoff

All 14 approved Rune tasks are complete. Reconciliation applies only the unique T2384 delta onto merged main `adc98b55e69af6be22e095126c81986d0d8e48a8`; the existing common T63/T2383/T2382 foundation is retained. Original feature worktree and paused T1734 work remain untouched.

## Source and review

- Publication worktree: `/Users/arjen/Documents/Codex/2026-10-03/task-4/transit-t2384-final`.
- Branch: `T-2384/publication`.
- Reconciled source: `fde318d5f8eedbef62f825bd9ad69889187c5f09`; tested pin: `b90e6f84255f01c3de39104ea59a9aa0c77c7acb`.
- All 271 production/configuration/isolation files compared are byte-identical to reviewed original tip `db775173`; merged main's test and documentation changes are preserved. Three documentation conflicts were resolved by retaining main and adding the feature.
- Four internal specialists cleared the current production delta. Review fixes correct the MCP guide's 13-tool list and restore the batch specs index row. Neither changes production behaviour.

`mutate_tasks` is one modern application tool call, with saved-only dry runs and 1–50 ordered update/status/comment items. It preserves original per-item receipt evidence, original argument binding, revision preconditions and atomic domain/result saves. Execution stops at the first unsuccessful or unestablished item; committed prefix effects remain. A complete correlated serialization-failure response is prepared before dispatch and later selected without reencoding. Caller retry/reconciliation guidance is in [the write contract](../../docs/mcp-write-contract.md#application-batch-task-mutations).

## Fresh reconciled acceptance

| Suite | Enabled declarations | Passing native cases | Source pin |
| --- | ---: | ---: | --- |
| Full macOS units | 2,409 | 3,049 | `b90e6f8` |
| Full isolated iOS units | 1,289 | 1,334 | `b90e6f8` |
| Full isolated iOS UI | 21 | 24 | `b8f9fc7` |

All three runs finalized normally with exit zero, exact enabled-inventory mapping, zero failures/skips/expected failures/native runtime warnings, and complete owned process drain without host signals. Only the UI fixture changed between pins; production, configuration and unit sources remain identical. Both fresh platform builds, the corrected UI incremental build, and final strict lint (596 Swift files and all guards) passed. The newly owned simulator was deleted; all other simulator UUIDs and existing stores were preserved.

The first fresh UI attempt completed 24 test bodies with four real fixture failures, then stalled in finalization. Its sampled owned runner was terminated (subprocess -15, wrapper 241), with no host signals and complete owned drain; that result is unfinalized and is not counted as acceptance. Three direct Settings assumptions were replaced by the existing overflow-aware toolbar helper. The portrait fixture now asserts a captured frame instead of timing out during a remote predicate query. All behavior assertions and all 21 declarations remain, and the full 24-case rerun passed. Native warnings are zero; ordinary XCTest debugger/animation-idle console diagnostics remain in logs.

See [publication-verification.json](publication-verification.json) for source-equivalence, native summaries, inventories, drain records and artifact hashes. The root independently checked every final native summary/inventory and all 15 recorded artifact hashes.

The original worktree's task14 evidence remains historical, including early qualified RED teardown failures. It is not substituted for the fresh publication results. No matching JUnit or line-coverage runner exists for this Xcode project; native results and inventories are retained without invented conversions.

## Publication and downstream boundaries

Earlier push attempts were rejected before execution by automatic approval review. The owner subsequently gave explicit trusted approval for this repository destination and source/documentation payload, with branch pushes approved and direct pushes to main excluded. The same normal push route then succeeded, and [PR253](https://github.com/ArjenSchwarz/transit/pull/253) was opened. Claude's first actual review and check passed; its suggestions were validated with no unresolved blocker/critical/major issue. Fresh final review and PR merge remain pending. The rejected checkpoints are historical; no workaround bypassed them.

The owner explicitly approved GitHub pushes, disclosure to the configured Claude reviewer, and eligible overnight merges. Earlier automatic approval denials are historical and have been resolved by that approval. PRPilot will record actual external review/check/merge outcomes on the PR and in the final parent report; this document does not preclaim them.

MacBook installed-client compatibility/activation is owner-deferred and is not a merge blocker. Before feature use, validate the latest-only 2026-07-28 connection, structured/text result compatibility and advertised `mutate_tasks` schema. No production/live task writes, guard-store recovery, production application/server launch, client setting changes, CloudKit changes or deployment were performed during this publication workflow. Ticket status remains unchanged under the parent's no-live-writes constraint. T1734's participating-commit factory and T572 navigation remain separate; no global import fence or task navigation URL is claimed.
