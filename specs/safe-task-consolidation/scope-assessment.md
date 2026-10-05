# T-2381 — Safe task consolidation: scope and name gate

Status: **proposed; awaiting scope, route and name approval**. Requirements, design, tasks and implementation have not begun. Approval requests go through the parent conversation; live MCP mutations remain paused.

## Recommendation

Use the **full spec workflow**, named **`safe-task-consolidation`**, for an explicit, bounded consolidation group with saved-only **preview → apply → undo preview → undo**. The caller chooses semantic equivalence and a canonical survivor. Transit preserves originals and their history, makes preservation and status choices visible, and refuses stale or unverifiable changes.

T-1734 already supplies `duplicate-of`, the common relationship store, graph validation, exact repair and canonical-chain resolution. **T-2381 owns the consolidation operation, its preservation plan, durable provenance and guarded reversal.** It does not introduce another relationship store or a persistence redesign.

This gate approves requirements work only. Product defaults below are proposals to settle during requirements, not silently approved requirements. Requirements, design, tasks and implementation each retain their own approval gate.

## Verified ticket and planning state

- Actual ticket: **T-2381 — “Add explicit duplicate links and safe task consolidation”**, Transit / Feature / Medium, UUID `F5CED508-F7C5-4AC0-B804-8945DF9B9B65`.
- A freshly advertised `query_tasks` schema and one cached, full saved read with comments verified the ticket at `2026-10-05T07:24:38.542Z`. It is Idea, has no comments, and retains revision `r1:ebd80bc9a55f82f56175f5723ad2b611ac196920bb616e41124e990b7d827a21`. Read freshness is unknown and import waiting was not requested; this is local saved evidence, not a claim about remote convergence. No task record was mutated.
- The source description motivates a **Prism cleanup**, where Abandoned status and prose comments carried duplicate mappings manually. Its acceptance calls for a six-ticket review before apply, no unique detail silently discarded, original history retained, explicit canonical readback, clear reasons/undo, and safe invalid/conflict outcomes. It explicitly builds on T-1734 and distinguishes T-649 task copying. This ticket is not a catch-all for unrelated duplicate-record incidents.
- The preserved initial scope at `bf4f40a9b758a6d4c71b4aadccb4409ff20538aa` says approval pending. T-1734's decision record verifies that the owner deferred T-2381 behind the relationship foundation; its scope/requirements approvals apply to T-1734, not this consolidation feature. The current instruction to resume spec work is not evidence of approval of unseen T-2381 documents.
- Freshly fetched `origin/main` is **`169ac244a11ebfbdacce3d4a25fcddfe395ac6d2`**, the verified T-1734 PR #254 squash merge. T-63/T-2382/T-2383/T-2384 are also in this base. Planning branch **`T-2381/safe-task-consolidation-spec`** uses that explicit base in `/Users/arjen/Documents/Codex/2026-10-03/task-6/transit`; the original `T-2381/safe-task-consolidation` branch remains at bf4f40a9. Other worktrees, canonical main and canonical `.kiro` are preserved.
- Read local Starwave scope/requirements guidance, repository `CLAUDE.md` and SwiftData/JSON rules, the merged typed-link requirements/ADR 4 and MCP write/read/result/batch contracts. No builds, tests, lint, review CLI, settings changes, deployment or implementation are part of this planning turn.

## Why full spec

Three triggers remain: survivor/content/status/undo choices are user-owned; the operation adds a public MCP contract and durable provenance; and an all-or-none local group differs materially from generic ordered per-item batches. A source revert cannot safely undo stored consolidation effects. The merged relationship foundation settles the common graph architecture, so the full spec should resolve only consolidation decisions.

## Included behavior

1. **Explicit selection.** Supply survivor and candidate UUIDs with a caller's reason. Search/full-detail reads can help review candidates, but the caller decides equivalence. Title similarity does not select a survivor or apply changes.
2. **Saved-only preview.** Show selected originals, covered revisions, direct/canonical mappings, exact proposed task/status/link changes and each preservation disposition. Exclude pending inserts/edits/deletions. Missing comments or unreadable/ambiguous evidence are errors, not empty history. Preview reserves no retry key and changes no domain record, receipt, guard, timestamp or allocation.
3. **Preservation.** Original UUIDs, original descriptions/metadata, comments with original authors/dates, and project/milestone associations remain inspectable. Caller-authored survivor edits explicitly account for transferred detail; remaining detail stays visibly attached to linked originals. Transit does not synthesise semantic summaries, move original comments or silently resolve conflicting fields.
4. **Protected application.** Revalidate the reviewed proposal, uniquely resolved originals and all affected saved task/link evidence. Preserve the existing dirty-context, exact-key replay, conflict and uncertain-outcome rules. The proposed group commits task/link changes, consolidation provenance and its terminal result together in the originating local store through the existing participating writer boundary.
5. **Explicit readback.** Return original-to-survivor mappings, actual saved changes, reason, operation identity and undo availability. Ordinary writes continue to address the selected original UUID. Retained snapshots and earlier receipts keep their original bytes and meanings; new reads reflect the new saved statuses/links.
6. **Guarded reversal.** Preview reversal against the applied operation's recorded evidence. Reverse only attributable effects that still match, preserve the original operation/history and record the reversal. A conflict rejects the whole proposed undo without overwriting later edits. Undo does not erase originals, receipts or durable retry guards, or use the existing abandoned-to-Idea shortcut.

Initial surface: MCP-first operation and structured readback, plus the read-only native reason/history presentation needed to understand consolidation alongside existing relationship navigation. Native consolidation editing, App Intent parity, unsupported navigation URLs, copying, semantic matching and regression/workflow features stay outside this proposal.

## Practical starting defaults for requirements

| Product choice | Recommendation to discuss |
| --- | --- |
| Group size and scope | One survivor plus up to five candidates, six total, in one project initially. Confirm whether six is the intended initial ceiling or only an acceptance example; do not invent unlimited groups. Keep project/milestone assignments unchanged. |
| Survivor and existing chains | Choose a uniquely resolved terminal canonical survivor. Preserve existing incoming links/chains; no automatic flattening or unrelated retargeting. Reject a candidate resolving to a different canonical target until the caller separately reviews/repairs that link through T-1734. |
| Closure | Preview an explicit move of unfinished duplicates to Abandoned; keep already Done/Abandoned statuses and survivor status unchanged by default. Confirm terminal-candidate participation and any optional survivor status edit in requirements. |
| Detail handling | Caller-provided survivor field edits with explicit source accounting; originals/comments stay in place. Preserve conflicts for caller decisions rather than choose longest text or last writer. |
| Commit boundary | One locally all-or-none group using the existing coordinator/owned save. Do not emulate it with `mutate_tasks` or post-commit compensating rollback. If this cannot meet the approved scope, reopen the relevant requirement before implementation. |
| Undo | Whole operation, conservatively rejected after covered edits to changed records. No selective/force-undo engine initially. Keep operation evidence with history; settle any undo time window explicitly. Seven-day receipt/removal-evidence retention does not itself define undo availability. |

The scope/name gate does not require every default to be chosen now. After it is approved, requirements should ask the few material product questions together and turn answers into observable acceptance criteria.

## Foundation boundaries

- **T-1734:** reuse its single typed occurrence/removal model, physical multiplicity/UUID ambiguity diagnostics, maximum 50 standalone link directives, exact occurrence fingerprints, current incidence-covered revisions and canonical resolution. A duplicate link alone never consolidates content or closes a task.
- **T-2380 / shared write coordinator:** maintain local store/tool/key/payload scope, source/affected endpoint guards, complete comment-covered revisions, read-only historical replay and original-key reconciliation after uncertainty. Dirty UI state must not be returned, saved or rolled back incidentally.
- **Participating guarantee:** coordinated MCP writers cannot interleave the synchronous final phase. Independent containers, App Intents/native paths outside that phase and imports may race; available saved faults are reported without reminting the original result or promising global CloudKit atomicity. Consolidation does not restart an all-writer persistence project.
- **T-2384:** `mutate_tasks` is ordered per-item work, stops after an unsuccessful item and provides no group transaction or durable batch receipt. It rejects link directives. A dedicated consolidation operation must define its own bounded group/result contract while reusing protected infrastructure.
- **T-63/T-2382/T-2383:** reuse saved capture, frozen evidence, original read/retention budgets, modern protocol and structured/text result parity. Classify and bound the new preview/history surface during requirements/design; do not assume it automatically inherits a covered-read budget or build a second snapshot engine.

Merged code does not establish installed endpoint/client readiness or live CloudKit verification. Those existing release prerequisites remain separately owned. No T-2401/T-2402 investigation is started or expanded by this spec.

## Risks to resolve in the gated documents

The requirements must make preservation review observable without pretending to judge semantic equivalence; define status, group and undo choices; and distinguish no-effect rejection, committed, active and uncertain outcomes. Design must account for additive same-store provenance, stale preview/undo, physical UUID collisions, missing/cyclic chains, encoding/save/crash failures, exact replay and historic compatibility. It must retain outside-writer/import qualifications and original data through failures and reversals. These are future design/verification topics, not permission for a build, fixture or persistence investigation now.

## Exact next gate for the parent

**Approve the full-spec route and name `safe-task-consolidation`, with T-1734 owning the merged duplicate-link/canonical foundation and T-2381 owning bounded caller-reviewed preservation, preview/apply/undo and durable operation history?**

Approval starts requirements discussion and drafting only. No T-2381 scope approval was found to reuse. Live ticket bookkeeping stays local while the MCP mutation pause is in force; no automatic status transition is performed even after this gate.
