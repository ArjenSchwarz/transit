# T-1734 — Typed task links: initial scope assessment

Status: **scope, full-spec route, name and listed types approved** by the owner at `Sentinel_2f1bde004c10819186e2b02bbc23023e`, as verified by the parent on 2026-10-03. Name: **`typed-task-links`**. Requirements, design and tasks remain separate gates. This starts the relationship foundation ahead of deferred T-2381 consolidation; T-2382 portfolio work stays active. Recommendations below describe the approved routing proposal; detailed behavioral choices are being taken through requirements review.

Public relation naming is consistently kebab-case following owner correction `Sentinel_54fa08e7dbb881919d2c718f23bfb0fe`: **blocks, blocked-by, relates-to, introduced-by, duplicate-of**. This changes the duplicate spelling in the initial proposal, without introducing an alias or approving detailed requirements. Historical source tickets/comments retain their original text.

## Recommendation

Specify one task-link foundation covering dependencies, associations, task-based regression attribution, and explicit duplicate relationships. Provide protected link mutations and saved-only detail/filter readback through the existing task tools. The foundation makes relationships visible to callers; linking a duplicate does not merge content, choose equivalence, close a task or perform undo.

Ask the owner to approve the scope, full-spec route and name before drafting requirements. Confirm any additional recently discussed type names that the checked sources do not establish. Requirements, design and tasks then have separate explicit approval gates. Implementation is not authorized by the instruction to start specs.

## Owner direction and verified checkout

- Owner message `Sentinel_491f1fff691c819189b3f7535e2465c3`: “It's probably more important/useful to implement 1734 first. So, table 2382 until that's done and expand 1734 with the various types that we've discussed recently as needing and then start with its spec”.
- The parent asked whether the pause meant T-2381 duplicate consolidation rather than T-2382 portfolio summaries. Owner clarification `Sentinel_4165673ac91c8191befe3f7d137a6d8c`: “Yes, typo, thanks for catching it”. Therefore T-2381 is deferred and T-2382 is not paused.
- Canonical `/Users/arjen/projects/personal/transit` remains on `main`, with its untracked `.kiro/` preserved. Local `main`, `origin/main` and live `git ls-remote origin refs/heads/main` matched **`201205bd4e786c7f152d8f99006b37da7da888c7`** immediately before checkout creation on 2026-10-03.
- Separate checkout: `/Users/arjen/Documents/Codex/2026-10-03/task-6/transit-t1734`, branch **`T-1734/typed-task-links`**, created from that explicit SHA. The T-2381 branch and scope document remain preserved at `bf4f40a`; this work does not reuse their identity.
- Applied the local Transit router and Starwave full-spec guidance, repository `CLAUDE.md`, SwiftData/JSON rules, and existing approved MCP foundation specs/ownership handoffs. No existing spec is edited.
- T-1734's description expansion was committed by the live MCP endpoint at `2026-10-03T12:40:19.440Z`, using fresh observed revision `r1:452d046508550ff12315735ba31cde3115827e1bcf9561a747fccbab23d249c4` and key `t1734-scope-expansion-20261003-7ce9e596`. Full readback exactly matched the appended description, retained all original description text, and verified name/type/priority/metadata unchanged. Current revision: **`r1:b829c52abd78e8fb23c1f3072930c63aa866560a793b0c9fd26481f5f3aec0da`**. Status remains **Idea** until scope approval.

## Exact relationship inventory and sources

| Type or projection | Established source | Proposed meaning/boundary |
| --- | --- | --- |
| `blocks` / `blocked-by` | Original live T-1734 description | Dependency edge and its inverse view. Support excluding tasks whose blockers are not done. The T-1733 → T-1732 dependency is the ticket's concrete motivating example. Whether both spellings are accepted mutation inputs or only projections is not yet decided. |
| `relates-to` | Original live T-1734 description | Association without dependency semantics. Symmetry and physical edge normalization must be specified rather than guessed. |
| `introduced-by` | Original live T-1734; T-1732 regression attribution; T-1733 workflow adoption | Directed task-based attribution. PR-number fallback remains possible where no introducing task exists; adding regression tri-state fields or changing filing/eval skills stays with T-1732/T-1733. |
| `duplicate-of` | Live T-2381 description, initial T-2381 scope at `bf4f40a`, and owner direction to expand T-1734 first | Directed duplicate-to-canonical relationship, with explicit invalid-target/cycle/canonical resolution semantics. Kebab-case spelling is settled by the naming correction; reverse/read projections and detailed semantics await requirements approval. No consolidation action follows implicitly. |

This is **four semantic relationship kinds**; `blocks` and `blocked-by` are opposite views of the dependency kind, not proof that two independent stored edges are required. “Depends on” in existing prose does not establish an additional kind. “Canonical” is duplicate resolution/readback, not an independently sourced relation type.

The reviewed ticket sources and checked recent parent discussion do not name `supersedes`/`superseded-by`, parent/child, follow-up, split-from or copy-of as requested types. Do not invent requirements for them. The word “Supersedes” in T-1734 describes replacing text-only dependency notes, not a supersession edge request. T-649 requests copying a task, which is not evidence for a copy-of relationship. If other recently discussed types were intended, the parent should obtain their exact names/use cases or source messages before requirements are written.

## Why full spec

1. **User-owned behavior:** blocker completion, symmetric association, duplicate chains, cross-project links, link edit semantics and native visibility have multiple reasonable behaviors not chosen by current code.
2. **Persisted/public contract:** SwiftData/CloudKit relationship representation, revisions and MCP inputs/results/query filters become data and consumer contracts. A source revert cannot safely undo persisted links.
3. **Contested architecture:** a dedicated link entity, task-owned serialized links and native model relationships have different identity, migration, inverse, revision and local transaction boundaries. The design must select one after requirements and feasibility review.

At the verified base, `TransitTask` has no typed task links. `TaskService.findByID` returns the first UUID match; display-ID lookup explicitly rejects collisions. T-2380 task revisions cover fields, assignments and complete comments, with no graph state. The implementation cannot inherit first-match identity behavior or assume current task revisions already guard link changes.

## Proposed included work

- A single typed task-link representation and reusable service with stable UUID identity, supported types, normalization, inverse read views, duplicate-edge handling and clear add/remove/change semantics.
- Validation of source/target identity and reference existence, self-links, allowed cardinality, cycles where relevant, and local graph invariants. Imported missing/ambiguous/corrupt references are reported without silently choosing a target or repairing data.
- Link mutation inputs in `create_task` and `update_task`, as the original ticket requests, integrated with the shared T-2380 write coordinator. Specify revision coverage and transaction boundaries for every affected record. A link edit must not flush or roll back unrelated unsaved UI edits.
- Saved-only task-detail relationship readback and `query_tasks` filtering by link presence/type and target, including the original unblocked-work use case. Include enough UUID/direction information that consumers stop parsing task descriptions for dependencies.
- Duplicate target/canonical readback suitable for later T-2381, with explicit safe behavior for chains and invalid graphs. No semantic equivalence classifier or automatic retargeting of ordinary writes.
- Compatibility with bounded capture, cursor/reusable snapshot evidence, structured results and generic batches after their compatible foundations merge. Frozen captures and historic receipts retain their original meanings.
- Focused eventual regression coverage for identity, graph/filter semantics, saved-only observations, protected mutations, migration/sync limitations and failures. No heavy test or build is part of this scope-assessment work.

Native surface recommendation for discussion: make relationships visible in task details using existing navigation patterns, with MCP creation/editing initially. A full native link editor, automated bug-blitz/next-task adoption and App Intent mutation parity should be included only if the owner explicitly chooses them. The original ticket establishes query support for those workflows, not permission to modify external workflow repositories.

## Ownership and exclusions

| Ticket | Responsibility retained |
| --- | --- |
| T-1734 | Link types, common storage/validation/service, protected link edits and relationship read/query contract. Duplicate linkage is included in this one foundation. |
| T-2381, deferred | Caller semantic-equivalence decision, survivor selection, detail preservation, consolidation preview/apply/undo, audit/provenance and operation recovery. No status changes or merging are triggered by a T-1734 duplicate link. |
| T-1732 | Regression yes/no/unknown data and PR-number attribution fallback where appropriate; do not silently absorb its tri-state feature. |
| T-1733 | Bug-filing/root-cause workflow and eval adoption; its dependency example informs T-1734 but does not authorize harness changes. |
| T-649 | Copying a task from the task detail sheet. |
| T-63 / T-2382 / T-2383 / T-2384 | Their approved capture/snapshot/protocol/batch contracts and present shared-file ownership. T-1734 coordinates integration and does not rewrite their specs or concurrently edit owned files. |

Exclude automatic semantic matching, content synthesis, task consolidation, duplicate closure, permanent deletion, full status history, a new task hierarchy, global CloudKit graph transactions, receipt/guard resets, and unsupported navigable URLs.

## Product choices for the requirements gate

| Decision | Recommendation to discuss, not an approved requirement |
| --- | --- |
| Vocabulary | Preserve existing meanings and add `duplicate-of`; kebab-case public spelling is settled. Any genuinely additional types need explicit use cases and approval. |
| Dependency orientation | One logical edge, with `blocks`/`blocked-by` read views; decide accepted input aliases and normalization. |
| Blocker completion | Begin with the ticket's exact “not done” rule: abandoned is not automatically completed. Decide missing/ambiguous/cyclic blockers and fail-closed unblocked filtering explicitly. |
| Cross-project links | Allow explicit same-store UUID targets across projects, since task dependencies/attribution need not share a project. Validate identities; never move either task or milestone. |
| `relates-to` | Symmetric association with idempotent duplicate-edge handling; decide how one edit covers both read directions and revisions. |
| Duplicate chains | At most one direct duplicate target per source; resolve canonical identity deterministically and reject self-links/cycles locally. Decide permitted chains, retargeting, terminal targets, and behavior under imported invalid graphs. |
| Link changes | Explicit add/remove operations rather than accidental full-list replacement; choose whether task creation/property editing and links save atomically together. The final MCP shape belongs in design. |
| Revision coverage | Guard link mutation using covered saved graph evidence, including affected inverse views where necessary; target status changes must affect blocker-filter results without rewriting history. Preserve receipt replay independently of live state. |
| Native/App Intent surfaces | Minimal task-detail visibility plus MCP mutation/query initially; decide editors and App Intent parity before requirements. |
| Limits and history | Bound links/request/query traversal; decide edge reason/audit need and deletion/dangling policy without turning T-1734 into consolidation provenance. |

## Foundation and integration prerequisites

- **Merged base T-2379/T-2380:** preserve bounded full-detail queries, complete comment-covered revisions, receipt key scope/expiry and exact historical replay. New link coverage needs an explicit version/migration decision; do not remint historical receipt tokens or rewrite saved outcomes. CloudKit-delayed edits are not detected by a local revision and later imports can conflict.
- **T-63:** saved-only immutable DTO capture, five-second covered-read deadline, eight unfinished physical read permits, honest freshness and coordinated publication. T-63 retains common read/server/type ownership until its verified handoff. Link traversal/filter capture must fit the same boundary without exposing unsaved or independently fetched graph state as coherent evidence.
- **T-2382, still active:** reusable captured views and summary reconciliation. Add graph evidence through agreed capture contracts; do not fabricate a second snapshot system or silently redefine summary counts.
- **T-2383:** approved MCP `2026-07-28` latest-only adapter and structured/text result parity. Existing historical receipt evidence stays frozen; task/project navigation is unavailable until supported, not guessed.
- **T-2384:** current owner of `MCPWriteCoordinator`. Its batch supports existing task update/status/comment operations with one target operation per batch item, ordered per-item commitment and no whole-batch rollback. Adding link arguments later needs agreed validation/receipt integration, not a competing coordinator or changed batch guarantee.
- **Schema/release:** select and verify an additive SwiftData/CloudKit-safe model and migration, including all ModelContainer/schema call sites and test factories. Production schema publication is a later explicit release prerequisite, not work authorized here.

The spec can progress after its gates while declaring foundation assumptions. Implementation and final integration wait for compatible merged contracts, a newly verified base, settled ownership transfers, refreshed actual tool discovery and separate implementation authorization. Existing endpoint query discovery lags the T-2379 repository selectors; live ticket readback is not evidence of client activation or schema adoption.

## Risks to resolve early

- **Graph identity/sync:** duplicate UUIDs, dangling edges and cross-device cycles cannot be solved by first-match lookup or a local check presented as a global guarantee. Design must define diagnostics and safe local mutation rejection.
- **Revisions and replay:** inverse views and graph changes may require multi-record preconditions; historical receipts, content tokens and no-ops must remain truthful. Replay precedes live validation under T-2380.
- **Capture cost/coherence:** dependency/canonical traversal and target status evidence must be bounded and saved-only within the shared observation boundary. Failure cannot appear as “no blockers” or “no duplicate”.
- **Meaning drift:** “abandoned means unblocked”, “introduced-by means regression=yes”, and “duplicate link means close/merge” are different product decisions; none follows implicitly from the relation label.
- **Scope creep:** verify every new type against a specific owner use case; keep consolidation, regression tri-state, workflow adoption and copying in their ticket owners.

No implementation, build/test, settings change, deployment, push or main/PR merge has occurred. Per-command escalation succeeded for origin verification and isolated checkout creation. The T-2381 record was not abandoned, deleted or moved to a new status; its deferral is conveyed by the parent direction and this assessment. T-2382 was not changed.

## Exact next approval for the parent

**“Approve a full spec named `typed-task-links` for T-1734, covering `blocks`/`blocked-by`, `relates-to`, `introduced-by`, and `duplicate-of`, with consolidation remaining deferred in T-2381? If other recently discussed relationship types were intended, which exact types and use cases should be included before requirements?”**

After approval, re-read T-1734 and perform its authorized transition to Spec with an approval comment. Then draft/review requirements and request their explicit approval. Future requirements/design peer reviews use the documented internal independent-peer fallback if external reviewers are unavailable; no unapproved external source disclosure is authorized.
