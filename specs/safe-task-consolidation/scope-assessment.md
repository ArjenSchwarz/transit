# T-2381 — Safe task consolidation: initial scope assessment

Status: **proposed; awaiting scope and name approval**. This is the initial routing and ownership review, not approved requirements, design, tasks, or implementation. All approval questions go through the parent conversation.

## Recommendation and approval requested

Use the **full spec workflow**, named **`safe-task-consolidation`**, for explicit duplicate relationships and a caller-reviewed preview/apply/undo workflow. A caller chooses semantic equivalence and the survivor. Transit preserves original tasks and history, exposes canonical linkage, and refuses unsafe or unverifiable changes.

Approve this scope, the full-spec route, the name, and the proposed ownership boundary with T-1734 before requirements begin. Product choices below are recommendations for requirements discussion, not implied approvals. Requirements, design, and tasks each require their own explicit approval. Implementation waits for those gates, separate implementation authorization, and compatible merged foundations.

## Verified inputs and isolated checkout

- Canonical checkout: `/Users/arjen/projects/personal/transit`, on `main`. Local `main`, `origin/main`, and a live `git ls-remote origin refs/heads/main` all matched **`201205bd4e786c7f152d8f99006b37da7da888c7`** on 2026-10-03. This includes T-2379 bounded/full-detail queries and T-2380 retry-safe writes. The live lookup succeeded with per-command escalation after sandbox DNS failed.
- Dedicated checkout: `/Users/arjen/Documents/Codex/2026-10-03/task-6/transit`, branch **`T-2381/safe-task-consolidation`**, created from that explicit SHA. The name is provisional until this gate. Canonical `main` and its untracked `.kiro/` are untouched; no existing worktree was removed or changed.
- Read local Transit router, Starwave creating-spec/requirements/design/tasks skills, repository `CLAUDE.md`, SwiftData/JSON rules, `docs/mcp-write-contract.md`, and approved foundation contracts/ownership handoffs. These are inputs; their worktrees are not edited.
- Fetched live full T-2381, T-1734, T-63, T-2382, T-2383, T-2384, T-649, T-1732, T-1733, T-2379, and T-2380, including comments and revisions. T-2381 and T-1734 are both **Idea**, with no comments or approved implementation. No ticket has been mutated by this work.
- T-2381 revision: `r1:ebd80bc9a55f82f56175f5723ad2b611ac196920bb616e41124e990b7d827a21`; T-1734 revision: `r1:452d046508550ff12315735ba31cde3115827e1bcf9561a747fccbab23d249c4`. Re-read before any later authorized workflow transition.

The connected endpoint exposes the current query tool schema, which has fewer selectors than the verified repository's T-2379 contract. Live reads establish ticket content; they do not prove that the running app or client schema has adopted the merged sources. Refresh tool discovery and verify the actual endpoint before implementation acceptance.

## Why this needs a full spec

All three routing triggers fire:

1. **User-owned behavior:** choosing a survivor, preserving unique detail, closing duplicates, cross-project handling, later edits and undo have several materially different acceptable behaviors. Code does not choose them.
2. **Persisted and public contracts:** typed relationships, canonical resolution, revision coverage, consolidation provenance and recovery evidence affect SwiftData/CloudKit data and MCP consumers. A source revert alone cannot erase the resulting stored links or safely reverse applied consolidations.
3. **Central architectural tradeoff:** an atomic local group transaction versus a resumable sequence has different failure, undo and receipt boundaries. T-2384's existing contract settles only its generic per-item batch semantics.

The user also expressly requests the full gated process. Existing code has no `duplicateOf` or typed task-link model. `TransitTask` stores task fields, assignments and comments; generic metadata is not an approved substitute for a relationship contract. Existing UUID lookup in `TaskService.findByID` takes the first match, so it cannot certify an unambiguous survivor. Existing `restore` moves an abandoned task to Idea; that does not restore a consolidation's prior state.

## T-1734 overlap and proposed ownership

T-2381 explicitly says to build on T-1734 and says that T-1734 owns relationship infrastructure. T-1734 presently requests `blocks`/`blocked-by`, `relates-to`, and `introduced-by`, link-aware create/update/detail queries and filters, and exclusion of tasks whose blockers are unfinished. It does not currently request `duplicateOf`, consolidation, or undo.

| Owner | Proposed responsibility |
| --- | --- |
| T-1734 | One reusable typed-link representation and identity rules; generic relationship service, persistence/schema integration and read/write/filter plumbing; dependency and attribution behavior already requested by that ticket. |
| T-2381 | Duplicate-specific constraints and canonical resolution; explicit survivor/duplicate selection; preservation plan; preview, application, audit/provenance, readback and safe undo/recovery. It adds the duplicate type through the agreed T-1734 extension point. |
| T-1732 / T-1733 | Regression classification, non-task PR attribution fallback, workflow/eval adoption. No regression tracking or skill changes in T-2381. |
| T-649 | Copying a task from its detail sheet. No task-copy feature in T-2381. |

**Recommendation:** retain two tickets and two owned implementations. T-2381 depends on a reviewed, merged T-1734 contract and compatible relationship infrastructure. Request an explicit parent decision to start/spec T-1734 separately or approve an expressly bounded foundation split; do not silently absorb its dependency filters, regression attribution, or general link editor into T-2381. T-2381 spec work can proceed on declared interfaces after scope approval, with design blocked where that contract is unresolved. If the owner chooses a joint delivery, record ownership and gated scope changes for both tickets before implementation; never build two relationship stores.

## Proposed consolidation boundary

1. **Explicit semantic decision.** The caller supplies a survivor and duplicate candidates by stable UUID. Existing text search/full-detail queries support reviewing candidates. Title similarity may suggest candidates but never changes records, chooses a survivor or declares equivalence. A new similarity engine is not required by the initial scope.
2. **Saved-only review.** Preview describes the actual saved originals, their revisions, proposed canonical mappings, changed fields/statuses, preservation dispositions and reason. Unsaved inserts, edits and deletions are not returned or saved as review evidence. Storage/comment failures are explicit unavailable/error outcomes, never empty history. Preview has no domain, receipt, guard, timestamp or allocation effect.
3. **Preserve originals and unique details.** Keep original UUIDs, descriptions, metadata, comments and source associations available. The plan identifies how each unique actionable detail reaches the survivor or remains explicitly linked and visible. Conflicting field values require caller decisions; no automatic last-writer, longest-description or title-only merge. Do not move historical comments in a way that loses original ownership, authorship or dates.
4. **Explicit canonical semantics.** Readback returns direct duplicate linkage plus resolvable canonical identity. Reject self-links, cycles, missing/ambiguous targets and invalid terminal resolutions; imported corrupt/dangling graphs return diagnostics without inventing a canonical task. Decide chain flattening, relinking and incoming-edge behavior in requirements. Duplicate relationships do not silently turn arbitrary writes to an original task into writes to its survivor.
5. **Protected application.** Revalidate locally saved identities, every relevant task/link precondition and the exact reviewed preservation proposal before new effects. Dirty shared-context state must never be flushed or rolled back incidentally. Preserve T-2380 retry/reconciliation guarantees. Responses distinguish commitment, rejection, in-progress and uncertainty, with saved mappings and recovery evidence.
6. **Safe undo.** Preview the reversal, reference the original operation/provenance, and check current covered state. Restore only attributable effects that remain safe to reverse; reject conflicts rather than overwrite intervening edits. Undo is not permanent deletion, receipt erasure, a new-key retry of an uncertain effect, or the existing abandoned-to-Idea shortcut. Preserve original history and the explanation of consolidation/reversal.
7. **Motivating acceptance scenario.** Six tickets can be reviewed together before any apply; all unique detail is accounted for; original records remain inspectable; readback exposes mappings directly; failures and later edits have defined outcomes; a safe reversal is reviewable. The six-ticket example does not yet settle the maximum supported group size.

Initial surface recommendation: MCP-first workflow and structured readback, with only the native presentation needed to make linkage/original history understandable. A full native consolidation editor, App Intent parity and new navigation URLs need explicit scope approval; T-2383 correctly reports unavailable links until a supported URL feature exists.

## Foundation contracts and merge prerequisites

| Foundation | Contract T-2381 must respect | Prerequisite |
| --- | --- | --- |
| T-2379 / T-2380, merged in base | Full comment-covered task revisions; saved receipt replay for seven days; local-store/tool key scope; uncertain outcomes require reconciliation. Revisions are content tokens, not monotonic versions. | Re-audit relationship/provenance revision coverage and historic receipt compatibility after schema changes. No claim of CloudKit-wide atomicity, cross-device deduplication or remote freshness. |
| T-63 | Saved-only immutable local capture, five-second covered-read deadline, eight physical read permits, explicit import/freshness evidence, frozen pagination and coordinated publication. | Wait for compatible merged capture/handler foundation. New consolidation preview needs an explicit deadline/classification decision; it does not automatically become a T-63 covered read. T-63 currently owns common read/server/types. |
| T-2382 | Reusable captured views and project summaries; status counts reconcile with snapshot queries and retain originals/identity diagnostics. | Consume its merged types rather than duplicate snapshots. Adding links does not imply new summary counts or retroactively alter retained captures. New captures reflect approved status effects. |
| T-2383 | Latest-only MCP `2026-07-28`, one RPC request per POST, structured/text semantic parity, frozen historical receipt presentation. | Wait for modern adapter handoff and verified client readiness; no legacy adapter fork or guessed navigation links. |
| T-2384 | `mutate_tasks`: 1–50 UUID-only distinct targets, supported update/status/comment operations, advisory dry run, ordered per-item commits, stop on first unsuccessful item, no whole-batch rollback or durable batch key. | Wait for merged write-coordinator changes and parent ownership transfer. T-2384 owns that coordinator now. Generic batches cannot currently create typed links or atomically update survivor plus duplicates. |
| T-1734 | Proposed typed-link foundation above; still Idea, no approved contract found in this base. | Explicit owner decision and separately approved/merged foundation or authorized split, plus compatible persisted-schema migration and CloudKit release prerequisites. |

Implementation starts only after relevant foundations are merged, the ticket branch is aligned with the newly verified base, conflicts and schema/revision effects are re-reviewed, live discovery is refreshed, and this ticket's own gates and implementation authorization are complete. A types-only scaffold or other ticket's component test is not delivery evidence. Do not change their approved specs to accommodate this ticket.

## Decisions to resolve in requirements

| Decision | Recommended starting point |
| --- | --- |
| Relationship ownership | Separate T-1734 foundation; T-2381 owns duplicate extension/workflow. Confirm sequencing now. |
| Duplicate status | Explicit reviewed move to Abandoned, with duplicate reason/link visible and survivor status unchanged unless requested. Decide whether Done/Abandoned candidates may be consolidated. |
| Field/detail preservation | Caller-provided survivor edits plus a disposition for each source detail/conflict; originals retained. Do not auto-synthesize or claim semantic preservation from a diff alone. |
| Cross-project/milestone groups | Same-project initial scope; do not move originals or invent a valid milestone assignment. Cross-project equivalence needs an explicit decision. |
| Commit boundary | Prefer one locally atomic consolidation group if durability/schema feasibility supports it; otherwise reopen the requirement and specify resumable partial progress before implementation. No whole-cloud guarantee. |
| Chains and relinking | Resolve a chosen target to an unambiguous canonical survivor; preview chain effects; reject cycles and unsafe implicit rewrites. Settle flattening and later survivor consolidation explicitly. |
| Undo conflicts/retention | Conflict-checked reversal of attributable changes with preserved audit history; decide group versus item undo, later added comments/links, provenance lifetime and relationship repair rights. Seven-day retry receipt expiry must not silently define undo availability. |
| Surfaces/limits | MCP-first, six-ticket acceptance fixture, bounded group size to decide; settle minimal native linkage/history presentation and whether standalone duplicate linking is needed. |

## Principal risks and verification direction

- **Lost actionable detail:** require explicit source accounting and tests with conflicting descriptions, metadata, comments, assignments and statuses. Originals must survive every failure and undo.
- **Schema/sync graph corruption:** verify additive SwiftData/CloudKit-safe link/provenance storage, duplicate UUID/display-ID collisions, dangling links, cycles, delayed imports and concurrent canonical changes. Fail closed locally without promising distributed locks.
- **Stale preview or unsafe undo:** verify source/survivor/link preconditions, comment-covered revisions, later local/imported edits and unsaved UI drafts. A retained snapshot is review evidence, not authority to apply stale state.
- **Partial commitment and retry expiry:** verify crash/save/result-encoding failure boundaries, exact-key replay, uncertain acceptance and replay after later edits. Never clear guards or permanently delete originals to recover.
- **Historic compatibility:** adding revision-covered fields cannot invalidate the meaning of frozen pages or saved receipt payloads. Design must define version/projection behavior without rewriting old receipts.
- **Scope collision:** keep general dependency/regression features in their owners, schema foundation singular, and shared-file changes coordinated after merges.

No heavy build/test, settings change, deployment, push, PR/main merge or implementation has occurred. Local spec commits are authorized. After scope/name approval, transition T-2381 to Spec using a fresh live revision and an approval comment, then draft and review requirements. The local peer-review-validator instructions provide internal independent peer fallback when external agents are unavailable; future gated reviews will use that documented fallback without disclosing source to unapproved external systems.

## Exact next gate for the parent

**“Approve the full-spec scope and name `safe-task-consolidation`, with T-1734 owning the typed-link foundation and T-2381 owning duplicate semantics plus preview/apply/undo? Should T-1734 be spec'd separately first, or should we propose an explicitly bounded foundation split for approval?”**

This gate authorizes requirements work only. Requirements approval, design approval, task approval and implementation authorization remain separate.
