# Typed task links — requirements review and owner gate

Review outcome: **ready for the requirements approval gate**. Scope/name/types are approved; these detailed requirements are not yet approved. Design, tasks and implementation have separate gates.

Public naming: **blocks, blocked-by, relates-to, introduced-by, duplicate-of**. All use kebab-case; no alias is proposed. Owner correction `Sentinel_54fa08e7dbb881919d2c718f23bfb0fe` changes spelling only and does not approve the full requirements.

Naming re-review: the design critic followed by both independent internal peers confirmed consistent spellings, unchanged relationship semantics, no alias and no implied requirements approval. The scope inventory now identifies spelling as settled while detailed behaviors remain pending.

Live ticket naming update is pending: full display-ID lookup now returns `Duplicate task identifier detected for displayId 1734`, so no write was attempted. A bounded direct `tools/list` read at the configured `http://localhost:3141/mcp` confirms the running server advertises the legacy query schema with no UUID batch/full-detail selector or duplicate scan tool. This is a live endpoint/data blocker, not stale connector metadata alone. No identity guard, task data, maintenance toggle or settings were changed.

A narrow exact-title search returns two T-1734 rows with the same task UUID `2E3A1518-78CA-43CA-9F96-516A51094EA3` and display ID 1734: one has no returned project and revision `r1:d7034fef6d06b45432923b4b03c3af1629d2f803f591ab5aeddee0a35ad62dc0`; the Transit-owned row has project UUID `8491AAC4-CC6C-498C-B93D-99DD68424226` and revision `r1:f6c920b55f5073f5fed605c2b63f06ee63837e416e3fd065fca2e2ef285964de`. Both are Spec and have one comment. A UUID write would not resolve that observed ambiguity, so the ticket change awaits a safe uniquely identified full read; no first-match write or repair was attempted.

## Review method and actual results

The local Starwave requirements skill requires a design critic followed by peer validation. The design-critic reviewer first examined draft checkpoint `b51b2a2`; two independent internal peers then validated the document and critic findings through technical-correctness and scope/maintainability lenses. Following refinement, the critic re-reviewed before both peers re-reviewed the final proposals.

The local peer-review-validator's external-model selector was active (`PERSONAL_PROJECTS=1`), but neither external Codex nor Kiro reviewer tool was callable. Its documented internal-peer fallback supplied two independent perspectives. These were internal agents using the available model, not distinct external model systems. No repository source was disclosed externally; no review CLI, build, test, lint or typecheck ran during the Asterism quiet window.

| Finding agreed by critic and both peers | Current requirement resolution |
| --- | --- |
| Invalid-edge repair could not be selected by target UUID alone. | Exact saved occurrence removal with source/endpoint guards; repair unavailable for ambiguous affected identities; nonexistent endpoints need no invented revision. |
| Current versus historic revision coverage was ambiguous. | Preserve r1 syntax, explicitly cover active incidence including empty sets, distinguish graph-covered evidence, conflict on old fresh-write tokens, and replay historical receipts first unchanged. |
| Batch endpoint overlap and strict item schemas were unsettled. | Standalone create/update link edits initially; T-2384 link directives reject before item/key acceptance. No implicit chaining or whole-batch graph guarantee. |
| Earlier graph validation did not establish commit-time safety. | Validate complete proposed local graph, affected invariants and endpoint preconditions at the same local commit boundary; explicit removal-only repair can reduce invalid evidence incrementally. |
| Imported-cycle reach, query orientation and occurrence lifecycle were unclear. | Direct-only blocker rule, cycle-member exclusion, explicit incoming/outgoing filters, direct incoming duplicate targets, new occurrence on re-add, and no domain effects for absent-edge no-ops. |
| Reusable view enhancement would change T-2382's approved contract. | Preserve reusable project/status options and capacity; graph filters unsupported, absent coverage explicit, ordinary graph captures frozen with scoped closure evidence. |

The critic's final wording gaps—mixed property/link edits, ambiguous endpoint repair and retained assessment wording—were addressed explicitly. Both final peer reports found no blocking technical, scope or compatibility contradiction for presenting the requirements. The technical peer's minor wording corrections to incoming duplicate-of and the decision log were also incorporated.

No material review disagreement remained after synthesis. Multi-endpoint task revisions are a conservative proposal with a real tradeoff: an unrelated target field edit can cause a link conflict. A separate graph token is an alternative, but would introduce a new concurrency surface; the owner is being asked to approve the conservative proposal, not a storage implementation.

## Choices the owner is approving

1. **Done-only blockers:** Abandoned does not satisfy a dependency. Exclude cycle participants and candidates with invalid direct evidence; do not recursively propagate a Done blocker's unrelated ancestry faults.
2. **Cross-project links:** explicit same-store UUID targets allowed without moving tasks or milestones.
3. **Attribution and duplicates:** multiple introduced-by sources; one direct duplicate-of target, chains and Done/Abandoned canonical targets allowed. No regression inference, redirect, merge or closure.
4. **Guarded delta edits:** at most 50 link directives per standalone create/update; source and affected existing endpoint task preconditions; locally all-or-none task/link/result commitment. No batch link support initially.
5. **Current revision transition:** retain r1 syntax but add active incident graph coverage, including empty sets. **Every pre-feature token becomes insufficient for fresh preconditioned writes, including status/property edits on no-link tasks.** Obtain a new full read after upgrade. Historical protected receipt replay remains unchanged and precedes fresh validation.
6. **Removal/re-add:** exact occurrence removal, incremental removal-only repair, ambiguous affected identities fail closed, no fake revision for a missing endpoint. A re-add gets a new occurrence identity; removed evidence has bounded design-defined retention rather than permanent consolidation history.
7. **Read surfaces:** ordinary queries gain graph filters and frozen saved evidence; reusable queries retain current project/status options and graph-filter rejection. Capture budgets/retention remain unchanged.
8. **Native surface:** read-only saved relationship visibility and exact-UUID in-app navigation; native editors and App Intent parity deferred.

## Remaining work and validation limits

Design must choose and verify the SwiftData/CloudKit-safe representation, migration and coverage marker, removal retention horizon, isolated local commit mechanism, exact repair locator, graph validation and bounded saved capture. Those feasibility checks belong to design and later authorized implementation; this review supplies no runtime or CloudKit convergence evidence. Shared-file ownership and compatible merged foundation prerequisites remain in force.

## Exact next request through the parent

**“Do the T-1734 typed-task-links requirements look good or do you want additional changes? Approval includes the choices above, especially old-token conflicts on fresh writes, standalone-only link mutations and unchanged reusable query filters.”**

An approval authorizes design work only. No implementation, deployment, push or main/PR merge is authorized.

## Requirements gate outcome

Approved by owner `Sentinel_36dc8dafea7c81919e7b060518fc9009` against corrected commit `748f474517d420498ccd9e54cf79f777e7763f57`. The pending request above is historical; next phase is design. The live duplicate investigation remains owner-managed.
