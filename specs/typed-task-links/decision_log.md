# Typed task links — decision log

Deferred destination: **T-2402 — Set up isolated CloudKit integration testing**, created and freshly verified by the parent through the installed UI (Transit, Idea/Research). No duplicate live ticket write.

Current concurrency contract: ADR 4 supersedes the independent-writer/import predicate-fence portions of the earlier feasibility decisions. Historical approvals and raw runtime evidence remain intact.

## Approved amendment — defer CloudKit test isolation

Authority: owner `Sentinel_42e647a603ac81918cbb949ed1ca67bb`, "The CloudKit test isolation can be a separate ticket. Proceed without it for now". Parent owns creating that ticket; no duplicate live write is authorized here.

Move reserved Development account/container/host setup and live additive schema/export/platform-deletion verification out of T-1734's task2 completion gate. Retain the optional uncompiled/unexecuted smoke source for the separate ticket. Verified local GREEN at aa5f56a (fresh build/preflight, four distinct drained closed-store stages, preserved fields/receipt bytes/physical multiplicity, empty new tables and three expanded metadata/control cases) can complete the remaining task2 boundary after review. This is a scoped deferral, not successful remote verification.

Keep all local imported-conflict tests, CloudKit-compatible model shape, foundation ownership/integration prerequisites and blocked-by edges. Complete task2 only under its amended local boundary, then proceed to task3 RED. Task4 now implements the owner-approved participating-write coordination, immediate saved validation and owned domain/receipt save boundary described in ADR 4; the independent-writer/import atomic fence is superseded. Account/schema/client activation and production promotion remain separately authorized actions.

## Quick Decisions

| Date | Decision | Authority / rationale |
| --- | --- | --- |
| 2026-10-03 | Corrected requirements approved; proceed design only. | Owner `Sentinel_36dc8dafea7c81919e7b060518fc9009`, corrected document commit `748f474517d420498ccd9e54cf79f777e7763f57`. Live duplicate investigation remains with owner; no ambiguous ticket mutation. |
| 2026-10-03 | Defer T-2381, keep T-2382 active, expand/spec T-1734 first. | Owner request `Sentinel_491f1fff691c819189b3f7535e2465c3` and typo clarification `Sentinel_4165673ac91c8191befe3f7d137a6d8c`, verified by parent. |
| 2026-10-03 | Scope, full-spec route, name `typed-task-links`, and vocabulary `blocks`/`blocked-by`, `relates-to`, `introduced-by`, `duplicate-of` approved. | Owner `Sentinel_2f1bde004c10819186e2b02bbc23023e`; permits requirements work, not unseen requirements/design/tasks or implementation. |
| 2026-10-03 | Live T-1734 description expansion committed with original text preserved, followed by approved Spec transition and comment. | Description key `t1734-scope-expansion-20261003-7ce9e596`; transition key `t1734-spec-scopeapproved-20261003-a8c43269`, committed at `2026-10-03T12:52:23.794Z`. |
| 2026-10-03 | Review locally through internal independent peers; no external source disclosure. | Local peer-review-validator permits internal fallback for unavailable external agents. `PERSONAL_PROJECTS=1`, but no callable Codex/Kiro external reviewer tool is exposed; quiet window also forbids review CLIs. Skill-required critic precedes two independent peer perspectives. |
| 2026-10-03 | No heavy validation during Asterism quiet measurement window. | Parent direction; spec-only reads, writes, reasoning and lightweight MCP calls permitted. Build/typecheck/lint/runtime checks deferred to later authorized implementation. |
| 2026-10-03 | All public relation spellings use kebab-case: blocks, blocked-by, relates-to, introduced-by, duplicate-of. | Owner correction `Sentinel_54fa08e7dbb881919d2c718f23bfb0fe`; parent selected consistent kebab-case. This supersedes the duplicate spelling in the scope approval summary; there is no alias/backward compatibility for this unimplemented feature and no requirements approval implied. Historical Transit comments remain unchanged. |

## Approved product decisions

Owner `Sentinel_36dc8dafea7c81919e7b060518fc9009` approved corrected requirements `748f474517d420498ccd9e54cf79f777e7763f57`. The following observable contracts govern design; implementation remains gated.

| Choice | Proposal and rationale |
| --- | --- |
| Blockers | Only effective Done satisfies a direct dependency; Abandoned remains blocking. This matches T-1734's “blockers are not done” wording without treating dropped work as delivered. Unknown/corrupt blocker state cannot certify unblocked work. |
| Cross-project | Explicit same-store UUID links allowed across projects; no task/milestone moves. Relationships need not share the projects of their endpoints. |
| Duplicate | One outgoing duplicate-of per source; chains resolve to the last task with no duplicate-of. No automatic flattening, status change, write redirection or content merge. |
| Surfaces | MCP mutation/query plus read-only native task-detail visibility; native editor/App Intent parity deferred. No workflow/harness edits. |
| Attribution | Multiple explicit task attribution sources allowed; introduced-by conveys attribution only, not regression classification. PR fallback/regression fields stay with T-1732. |
| Link edits | Explicit additive/removal delta, omitted delta leaves links unchanged. No whole-set replacement; task creation plus links or property update plus link delta commits as one local protected operation. |
| Preconditions | Existing source task expectedRevision plus current task revisions for other affected existing endpoints; incoming/inverse changes must not bypass their covered revision evidence. Commit validation covers graph invariants with the complete proposed result. Retargeting duplicate-of is explicit remove/add. |
| Incomplete synced graphs | Invalid edges retained/reported; requested explicit removal may repair them. No automatic deletion, invented target or global convergence claim. |
| Query compatibility | Ordinary task queries gain relationship filtering. T-2382 reusable queries retain approved project/status options; graph filters remain unsupported, and absent graph coverage is explicit. Existing five-minute/eight-view/16-MiB accounting applies. |
| Batch boundary | Link mutations initially use standalone create/update only; batch link directives reject as unsupported shape. This preserves T-2384's approved schemas and avoids incidental endpoint overlap/revision chaining. |
| Imported dependency cycles | Exclude cycle participants and candidates with invalid direct evidence, without recursively propagating ancestry faults through Done blockers. |
| Removal identity | A new re-add creates a new occurrence identity. Exact invalid-occurrence removal may repair incrementally; ambiguous source/repair identities or existing affected endpoint UUIDs fail closed as repair unavailable. A missing endpoint needs no invented revision. Removal evidence has bounded retention separate from active content revisions. |
| Revision transition | Retain r1 syntax with explicitly graph-covered current hashing, including empty active incidence. Old pre-feature tokens conflict on fresh writes; historical exact receipt replay remains first and unchanged. |

### ADR 1 — Proposed revision boundary for inverse relationship edits

Status: approved observable contract; storage design pending.

**Context.** A relation visible from two tasks changes both task-detail observations. Guarding only the request source would permit silently changing another endpoint's observed incident links and would leave its record revision inconsistent with its detail payload.

**Proposal.** Current task revisions cover normalized active incident occurrence identity/type/endpoints in addition to existing fields/comments. New mutations supply source expectedRevision and current endpoint task preconditions for every other existing task whose active incident membership changes. Target labels/status, removed-evidence retention and recursively resolved canonical paths remain separately identified observation evidence, not source revision-owned fields. Fresh reads/commits identify graph-covered evidence; pre-feature tokens cannot authorize fresh writes. Historical exact receipt replay remains independent and unchanged.

**Alternatives.** A separate graph/link-set token could avoid revising task tokens but adds another independently versioned optimistic concurrency surface. One-source-only coverage is smaller but cannot guard inverse changes safely.

**Consequence.** Design must prove a local all-or-none domain/link/result save and choose migration/coverage-identification details within the proposed r1 format and fresh-token transition, without rewriting historic receipt/page evidence. This is a proposed observable contract, not a selected storage architecture or guarantee about unimported CloudKit changes.

## Requirements review resolutions

The design critic and both independent internal peers agreed on four P1 gaps in the initial draft: exact invalid-edge selectors, fresh revision coverage transition, batch compatibility and graph validation at commit. The draft now states the observable resolutions above. They also agreed on direct blocker-invalidity rules, explicit incoming/outgoing query behavior, occurrence identity/no-op semantics and saved-view compatibility. The owner approved these observable resolutions with the corrected requirements; they do not select a persistent storage design.

## Design decisions

### ADR 2 — Platform deletion separate from bounded repair evidence

Status: approved at `56e9ad5` by owner `Sentinel_775be6f4fc6c8191a9d7ccf1d0c04557`; seven-day horizon selected.

**Context.** The owner challenged an arbitrary30-day retention proposal (`Sentinel_69d82973f3b4819185f45cfc084147ea`). Personal-tool use does not justify an enterprise audit window. A single active/retired row whose retirement evidence expires couples garbage collection to link state and risks treating late imports as revived links.

**Decision proposed.** Delete the exact active occurrence and save small removal evidence in the same existing store/terminal-result commitment. Leave CloudKit deletion/history management with SwiftData/Core Data. Expire only convenience evidence; it cannot create an active occurrence. Recommend seven days to match existing receipt retention, not as a sync-convergence guarantee.

**Alternatives.** Indefinite application tombstones violate bounded repair-history intent and add a custom distributed protocol. No removal evidence loses approved exact-removal/no-op recognition. Thirty days has no demonstrated need. A separate non-CloudKit store would break the same-store atomic save boundary.

**Consequences.** One additional small entity/schema integration; exact unknown selectors after expiry fail closed. Remote imported conflicts stay explicit. The application never purges framework sync history on this horizon. The owner approved the seven-day horizon and reviewed architecture at checkpoint `56e9ad5`; the earlier retention question itself was not approval.

### ADR 3 — Extend the merged coordinator's clean-context policy

Status: approved at `56e9ad5` by owner `Sentinel_775be6f4fc6c8191a9d7ccf1d0c04557`.

**Context.** Existing coordinator baseline saves can publish pending UI edits; T-2384 owns clean-context policy work. A standalone link operation changes multiple task observations and must not flush or roll back drafts.

**Decision proposed.** Generalize the merged policy for link-bearing standalone create/update, preserve receipt-first read-only inspection while dirty, check every post-await success/error path, and validate proposed graph/preconditions immediately before the sole domain/result save.

**Alternatives.** A second coordinator duplicates retry/receipt semantics. A separate graph store cannot commit task/edge/result together. MainActor alone does not serialize store imports; an unproved fence is not an atomicity claim.

**Consequences.** Wait for foundation handoff and verify disk-backed save/import boundaries first. If proof fails, graph writes stay unavailable and the design must be revised before implementation continues.

| Minor design choice | Rationale |
| --- | --- |
| Scalar endpoints; no uniqueness/cascades | CloudKit compatibility and preserved dangling identity evidence. |
| l1 occurrence fingerprint of immutable values | Exact removal selector without exposing physical store identifiers; same-UUID physical collisions remain unavailable. |
| No new PBT dependency | Seeded Swift Testing graph generators plus independent reference algorithms fit the existing project. |

## Design gate outcome

Owner `Sentinel_775be6f4fc6c8191a9d7ccf1d0c04557` approved reviewed checkpoint `56e9ad5`, including seven-day removal recognition and the early migration/atomic-save feasibility gate. This authorizes task planning only. Approval relayed by parent with the immediately preceding design/seven-day/feasibility-gate request. The separate testing approval does not authorize T-1734 implementation. Live Transit writes remain paused; bookkeeping stays local.

## Task and conditional implementation approval

Owner `Sentinel_d1ba9360969c81918777711b2420bfc7` approved task checkpoint `18a268f7604889de6328e224ddf45d516ea8654b`: “Tasks approved. You can continue implementation when the code is ready for it.” Parent relayed this against the task/conditional implementation request `Sentinel_20c841bb16e48191b679d21c6a049161`. No further readiness approval is required. Compatible merged foundations, explicit shared-file handoffs and feasibility gates remain technical prerequisites. T-2382 holds the exclusive heavy-test slot; request a concrete isolated test slot when source is ready. Live mutations, client activation and deployment remain held.

## RED/ GREEN boundary reconciliation after actual closed-store evidence

Parent directs reconciliation without a new user approval gate. Internal design-critic review confirms focused missing-entity RED and process-separated seed/legacy controls plus missing-model upgrade RED. Successful eight-entity migration, completed scalar metadata assertions, source parity GREEN and real development CloudKit evidence belong to task2's completion gate; requiring them before task1 RED completion would demand GREEN circularly. No approved DAG contradiction was found.

The critic identifies one real task1 source-completeness gap: its third bullet requires substantive opt-in development schema/platform-deletion fixture source. The existing local precheck is explicitly insufficient. Prepare the real typed source outside default runs, with compilation deferred until task2 declarations and execution deferred until separately cleared development host/account/schema prerequisites. Once that source exists and is reviewed, task1's RED completion may unblock task2 source work; no successful external execution or model registration is required to complete RED. Task2 retains every local/external feasibility gate before task3.

Seven schema-factory and compile-list inventory is proposed in tests/typed-task-links/schema-registration-inventory.md and its adjacent unapplied patch at `b168ef1e6cce6622cdbf0700de78e41ef03046ce`. No handoff is inferred, and no shared source is edited until parent agrees the exact split. This context exposes no callable cross-thread messaging tool; the parent must route the concrete inventory to T-63/containment and identify current probe/fixture ownership. Task2's new model definitions are already approved scope, not a new feature decision. No source disclosure to an external reviewer, heavy run, live mutation or schema publication occurs in this reconciliation.

Final critic review confirms the substantive smoke source closes task1's remaining source gap; timeout sampling before exact-child teardown is prepared in `cffece1b597e975038d3b8deb023e89345ad949f`. Rune now marks task1 RED complete and returns task2 next. `red-boundary-review.md` records the evidence and preserved task2 completion gates. Task2 source is pending the agreed exact shared-file split; no shared production source has changed. This is RED completion, not local migration GREEN or external environment verification.

## ADR 4 — Participating Transit writes with detected outside-writer conflicts

Status: guarantee choice approved by owner `Sentinel_c95239aefa6481919303c2353b8a9e9c`; amended requirements/design/tasks approved by owner `Sentinel_08cb318218788191a85da25d1206979f` at `a64e595c439db6d62e46c85888f37130d53269fa`.

**Context.** Source inspection found no supported full-predicate fence in the current SwiftData DefaultStore architecture. The read-first transaction counterexample passed at `27fa36e`; the separate internal-save/closure-abort prerequisite failed six expectations at `c8bbd127`, while eight imported-policy controls passed. These are localized evidence about the tested approaches, not universal impossibility. Preserving protection against all independent writers/imports would require a persistence-foundation design change.

**Decision.** Parent presented the strict persistence-redesign alternative and recommended coordinating Transit writes, validating before saving, and detecting/reporting conflicts from other writers or sync, explicitly saying a race can temporarily leave inconsistent links (`Sentinel_6b01a4425ad08191936c423d1d1b2ada`). Owner answered: “Let's go with the simpler option.” Participating writes are executions through the shared MCPWriteCoordinator (standalone and T-2384 per-item batches), with a synchronous MainActor validation/apply/stage/save phase and clean checks around preparation. Same-context MainActor native/UI work cannot interleave that phase; unsaved drafts remain guarded. Independent containers, external native/App Intent paths and platform imports are outside that coordination guarantee.

**Preserved guarantees.** Reject unsafe/ambiguous saved evidence observed before applying; require current source/affected endpoint revisions; preserve explicit removal-only repair, precise occurrence identity, read-only dirty replay and all receipt/key/recovery rules. Save the originating task/link/removal/terminal result together in the same store. Preserve bounded captures and truthful saved conflict diagnostics; no automatic repair, original rewriting or permanent deletion shortcut.

**Tradeoff.** An outside writer may change an endpoint or insert cycle/cardinality/identity/removal conflicts after validation but before the originating save. The save may still commit; inconsistent evidence may remain until explicit repair. Subsequent saved projections derive current assessments and identify available invalid evidence; valid endpoint status changes are not labeled historical race conflicts, without rewriting its immutable terminal receipt or claiming no effect. This local race is acknowledged separately from unimported remote changes. There is no all-independent-writer atomic validation/save guarantee, persistence-redesign enablement gate, post-commit compensating rollback or global CloudKit atomicity claim.

**Evidence/task treatment.** Preserve raw counterexample/abort fixtures and retained results; recast them as documented limits rather than required failing completion gates. Tasks3/4 retain their stable IDs and Red/Green order but test/implement participating coordination, saved validation and all-or-none owned commitment. Their existing downstream edges now refer to that local implementation boundary. Do not mark incomplete tests/implementation complete merely from the scope amendment. T-2402 remains deferred. No new product decision is outstanding; final amended-document approval is the local Starwave iteration gate.

### Amendment review synthesis

Design-critic review preceded two independent internal peer-validation perspectives (correctness and scope/maintainability). External Codex/Kiro review tools are unavailable in this environment; the documented peer-review-validator fallback was used, without external source disclosure. The critic requested exact participant wording, removal of residual proven-boundary labels, and differentiation of ordinary status assessments from provable race faults; those changes were applied. Both peers found the final package coherent with no core blocker or new product decision. Raw limit evidence is not reclassified as atomicity success. Retained outcomes preserve their original observed/owned meaning even when later saved readback has different revisions or assessments.

Rune parses 22 tasks, with two complete, one in progress and 19 pending; stable IDs, statuses, streams, requirement references and dependency edges remain intact. All 39 acceptance criteria are covered. Next implementation step after final amended-document review: task3 source-only participating-phase/fresh-saved-resolution controls and allowed-race fixture amendment, followed by task4 minimum shared-policy owned-save integration. Actual graph diagnostics follow tasks5/6 and21/22. Heavy execution still requires a separately assigned drained slot; T-2402 remains deferred.

The narrower guarantee choice is already approved. Local Starwave requirements/design/tasks skills require final approval of edited documents; this review asks whether those documents correctly express that choice, not whether to choose the same tradeoff again.

## Amended-document approval and implementation continuation

Owner `Sentinel_08cb318218788191a85da25d1206979f` replied “Approved” to parent `Sentinel_8a8182fee7d88191be122baaf7e97604`, which explicitly asked for final approval of the amended requirements/design/tasks after phone delivery. Approved checkpoint `a64e595c439db6d62e46c85888f37130d53269fa`. Parent authorizes continuing existing implementation at task3 boundary-test amendment then task4 under the participating-writer guarantee. No further document/readiness approval is pending; do not restore the independent-import predicate fence or T-2402 gate. T-2382 currently owns the full macOS verification slot, so source preparation only; report a concrete focused runtime job when ready. Shared source editing ownership and live-data holds remain unchanged.
