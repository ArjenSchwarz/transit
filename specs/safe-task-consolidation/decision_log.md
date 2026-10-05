# Safe task consolidation — decision log

## Approval state

| Gate | Evidence / state |
| --- | --- |
| Resume planning | Owner `Sentinel_c4dd914497c08191bc5612ccddd5449c`: “While Asterism is ongoing, start on the spec for 2381 and start planning the work for Meddy”. This branch owns T-2381 only. |
| Scope, route and name | Approved by owner Sentinel_330b41f7115481918e53c2e1480c5dbc, replying “Approved” to Sentinel_efafa185b128819198b0fb0f045ba886; exact reviewed checkpoint 2bc58bbd. This approval permits requirements only. |
| Requirements / design / tasks | Requirements approved by Sentinel_1e5655b5fba48191b5a5be8602d0cf1b against b1d02591dd214f1d2ca6cf3f196b52b01058076a and Library packet libfile_25ec8d9d5da48191875d258b9c419406. Design approved by Sentinel_21b7c9588ec88191b7d78732649d99a9 against 7714e30121baf55f51086924269bd253dc8bfd9b and Library packet libfile_31bf6900be6481919971a2a80d72763c. Task plan approved by Sentinel_30bf9cc075e48191997f3eaee84ba68d against 5921d7954304e4c5df34eca686f15fd7d89acb14 and Library packet libfile_fbcfd24510a88191b3fecffe6e61a9f3; conditional implementation authorisation recorded below. |
| Implementation | Authorised by Sentinel_30bf9cc075e48191997f3eaee84ba68d. Parent confirmed resource release and later returned the slot after the urgent Meddy fix. Phase 1 implementation and critic recheck complete; phase 2 proceeds in one stream. No further approval gate. |
| Live bookkeeping | Paused with live MCP mutations; local records only. |

## Quick Decisions

| Topic | Decision / basis |
| --- | --- |
| Ticket identity | Cached full saved read at 2026-10-05T07:24:38.542Z verifies T-2381 “Add explicit duplicate links and safe task consolidation”, UUID F5CED508-F7C5-4AC0-B804-8945DF9B9B65, Idea/Feature, revision r1:ebd80bc9a55f82f56175f5723ad2b611ac196920bb616e41124e990b7d827a21, no comments. This is local saved evidence with unknown remote freshness. |
| Current base | Fresh origin/main 169ac244a11ebfbdacce3d4a25fcddfe395ac6d2 includes verified merged T-1734 PR #254 and the MCP foundations. |
| Preserve prior work | Original T-2381 branch/bf4f40a9 remains intact. New planning branch T-2381/safe-task-consolidation-spec carries a copy of its initial document; canonical and T-1734 worktrees are untouched. |
| Foundation ownership | Owner-approved T-1734 scope/ADR 4 is inherited as the foundation: one typed relationship implementation including duplicate-of/canonical resolution, participating local owned saves, truthful outside-writer/import limitations. T-2381 approvals are separate. |
| Quiet profile | Read-only source/docs, local Git bookkeeping and internal document review only. No heavy commands, review CLI, settings, deployments or live writes while Asterism runs. |

## Product choices approved

All five product choices in requirements checkpoint b1d02591 were approved by Sentinel_1e5655b5fba48191b5a5be8602d0cf1b: six same-project participants, unfinished-candidate closure, survivor description/metadata edits, guarded whole undo, and history without separate expiry. The exact approval is recorded below. The scope document retains its historical gate text.

## Recovery review — 2026-10-05

Recovered and read the interrupted worker's saved scope and this log without replacing either. Verified the cached full ticket response at `/tmp/t2381-spec-source.json`, the original scope checkpoint `bf4f40a9`, current branch/base (`f791bd0d` / `169ac244`), and merged T-1734 ADR 4 plus the MCP write contract. Related task-6 T-1734 worktrees were clean at inspection. No prior T-2381 scope approval was found.

Read-only scope review found no blocking mismatch: caller-selected equivalence, preserved originals/history, canonical readback and reversible consolidation match the actual ticket; duplicate-link ownership and participating synchronous pre-save validation/owned commitment match the merged foundation. Same-project/six-total limits, status policy and undo conflicts/retention remain proposals rather than approved requirements. A full peer/critic review of requirements/design/tasks remains for those gated phases.

Next gate is unchanged: scope, full-spec route and name approval through the parent. No requirements, design, tasks, source implementation, heavy commands, live bookkeeping or maintenance were started. Existing uncommitted documents are checkpointed together; original branch, canonical main and other worktrees remain untouched.

## Scope approval and requirements proposals — 2026-10-05

Parent relayed exact transcript: Assistant Sentinel_efafa185b128819198b0fb0f045ba886 asked approval of preview/apply/undo preserving originals/history on T-1734 links/canonical resolution, explicitly deferring group limits, status handling and undo retention. Owner Sentinel_330b41f7115481918e53c2e1480c5dbc replied “Approved”. Record against reviewed scope checkpoint 2bc58bbd.

Name safe-task-consolidation is retained. Per parent delivery instruction, requirements questions and proposed choices are collected in one reviewed packet for the parent gate rather than separate child prompts. Draft recommendations: six total/same project; close unfinished candidates only; survivor description/metadata edits only; whole undo with full covered-revision conflicts; retained operation history without a separate time expiry. These are not approved product decisions. Requirements review follows design-critic then two independent internal peers; no external review CLI or heavy commands.

## Requirements review synthesis — 2026-10-05

Completed self-review (eight one-line stories, 28 numbered EARS criteria with unique anchors and trailing Markdown spacing), then design-critic, then two independent internal peer perspectives: correctness/edge cases and product/preservation/maintainability. Internal consultation was used under the explicit quiet-profile instruction; no external model/review CLI was run despite PERSONAL_PROJECTS=1. The critic and product peer rechecked the final deltas and found no blocking issues; correctness peer found no further blockers after its clarifications. No runtime validation is claimed.

| Finding | Resolution / reasoning |
| --- | --- |
| Read budgets were left to design classification | Preview, undo preview and new history reads now share existing five-second/eight unfinished-read contract. Existing snapshot quotas apply only when evidence is retained; durable operation history is separate. |
| Caller review was not observable / acknowledgment conditional on edits | Every apply requires explicit acknowledgment of its reviewed preservation plan, including retention-only plans. This is not a semantic-completeness certification. |
| Candidate preservation was unnecessarily binary | Mixed incorporated/retained detail is allowed, with source/field attribution and retained-detail explanation. |
| Undo protection did not explicitly cover participating writes or exact reviewed reversal | Both apply and undo use the participating protection; undo requires reviewed reversal/evidence and rejects stale/unreadable evidence. |
| History exposure was conditional | New full reads and native detail of recorded participants must show history or explicit unavailable/over-limit evidence. |
| “Any covered change” exceeded content-token detection | Proposed undo checks current covered content/evidence against applied state. Edit-then-identical-restore does not claim temporal detection or require monotonic/persistence redesign. |

All findings were accepted as observable scope-consistent clarifications. Review consensus: existing typed links/canonical resolution, guarded owned local saves and truthful independent-writer/import limits are sufficient foundations; no new architectural choice is required in requirements. The five proposed product choices remain unapproved and belong in the parent requirements gate. No requirements approval, design, tasks or implementation follows from these reviews.

## Requirements approval — 2026-10-05

Assistant Sentinel_61c39a158f54819196306a4b797da48f presented all five choices (six same-project participants, abandon unfinished candidates, survivor description/metadata edits, guarded whole undo, no separate history expiry) and asked whether requirements look good, explicitly saying approval moves to design. Owner Sentinel_1e5655b5fba48191b5a5be8602d0cf1b replied “Approved”. Parent records exact checkpoint b1d02591dd214f1d2ca6cf3f196b52b01058076a and single Library packet libfile_25ec8d9d5da48191875d258b9c419406. All five choices are now accepted. Requirements file remains the exact approved text/checkpoint.

Design research reads actual merged coordinator/owned scope/typed occurrence, read capture/publication/retention, task snapshot/revision and native detail/navigation sources. Context7 tools are unavailable; official Apple documentation references were checked but exposed JavaScript/unsupported-Markdown pages, so no unsupported atomicity or sync guarantee is inferred from them. The repository’s approved T-1734 ADR4 and implementation contracts govern the local writer boundary. No builds, tests, lint, typecheck or heavy review CLI ran; Meddy owns the heavy slot.

## Proposed design decisions

### ADR 1 — Immutable same-store operation and reversal evidence

Status: approved at 7714e301 by Sentinel_21b7c9588ec88191b7d78732649d99a9.

Context: approved whole undo and permanent inspectable history need durable attributable before/after evidence beyond seven-day receipts, while CloudKit can import physical collisions and partially available history.

Decision: one additive TaskConsolidationEvent entity records immutable apply/reversal events with scalar participant lookup and versioned bounded payload. Guard original operation history separately with o1; task r1 remains the merged field/comment/link token. Both event and actual group effects/terminal receipt share the existing owned save.

Alternatives: an expiring receipt alone loses long-lived undo/history; mutable task-local reversed flags can overwrite provenance and require rewriting generic task tokens; separate persistence cannot use the existing same-store save boundary. Costs: additive migration and explicit history decode/ambiguity/byte checks. No new distributed coordination guarantee follows.

### ADR 2 — Existing retained publication for exact reviewed proposals

Status: approved at 7714e301 by Sentinel_21b7c9588ec88191b7d78732649d99a9.

Decision: immutable preview values occupy one ordinary retention root for five minutes, using the existing eight-root/16-MiB publication path and exact reviewId/p1 comparison. Apply/undo load the server-held plan and revalidate saved task/link/operation evidence. Exact receipt replay precedes review/current-state checks.

Alternatives: trusting an editable client plan/digest alone does not tie execution to the actual reviewed preview; durable preview rows add writes to a read-only preview and another cleanup/retry surface. Cost: after expiry/restart a caller must preview again for new execution. A retained terminal result still replays under its original seven-day receipt contract.

| Minor design choice | Rationale / requirement basis |
| --- | --- |
| 256-KiB encoded immutable event payload | Bound one history record and avoid copying complete comments; excessive original changed values/accounting reject explicitly before domain save. The limit is a design choice for approval, not an inferred CloudKit guarantee. |
| Fixed scalar candidate slots | The accepted maximum is five candidates; scalar lookup needs no to-many predicate, relationship/cascade or additional member model. |
| Complete metadata replacement; explicit-null description | Match explicit reviewed fields; keep absence versus null/request identity and preserve exact raw values for reversal. |
| Combined graph delta before effects | Per-source validation is not a group commit; use final combined graph projection and one owned application/save. |
| Operation IDs do not become navigation links | Current result presentation recognises task/project references only; participant references reuse that contract and no URL feature is invented. |

## Explain-like design self-validation

Beginner: the caller reviews six saved originals and a plan, then confirms that exact plan. Transit closes duplicate work while retaining the originals and a small permanent account of what changed. Undo checks that current originals still match the recorded result before restoring only those changes; an expired preview requires another review, not loss of history.

Intermediate: ordinary retained preview roots carry immutable values and p1; shared coordinator acceptance/replay precedes owned fresh r1/link/o1 checks. One no-save group service changes allowed fields/occurrences and inserts an immutable event with its terminal receipt in one originating local save. Native history uses saved value observation and existing unique navigation.

Expert: current-content tokens are not monotonic change history; exact raw dates/metadata and created occurrence tuples support attributable reversal. Immutable apply/reversal multiplicity and o1 expose imported history conflicts without reminting r1 or historical receipt bytes. Nonparticipating writers/imports can race final validation/save; later saved diagnostics retain actual commitment and never compensate it automatically.

Self-validation clarified commit-time dates/IDs in the reviewed plan, unique physical common-project resolution, combined graph validation before effects, actual created-occurrence return evidence, and explicit legacy/current history coverage. Load-bearing additive closed-store/owned group save and bounded payload/capture behavior have early runtime verification/failure paths in the design. No runtime proof is claimed now.

## Design review synthesis — 2026-10-05

Self-validation used explain-like at beginner/intermediate/expert levels and an explicit requirement coverage/parity audit. Design-critic reviewed first; two independent internal peers then reviewed correctness/edge cases and integration/maintainability. The critic and integration peer rechecked final deltas. No external model/review CLI or runtime validation was used under the quiet-profile instruction.

| Finding | Resolution / reasoning |
| --- | --- |
| Partial task/history capture cannot establish undo availability | Capture all operation participants, complete comments/incidences and required canonical dependencies in the same stable boundary. Closure is supplementary, not selectable query scope. Native uses the shared boundary helper. |
| Saved-only fetch before save misses new links/events | Existing occurrence apply returns actual tuples. Derive applied r1 and committed o1, history and terminal records from authoritative staged values including actual created IDs. |
| Raw accessors can hide corruption | Strict known statusRawValue and string-dictionary metadataJSON validation before planning; preserve exact raw status/metadata/date values in attributable restoration. |
| Native provider lacked named admission/deadline integration | Expose existing Foundation-based physical read lifecycle across platforms with value-result delivery; app-lifetime one coordinator shares eight slots/five-second deadline, keeps timeout workers charged until cleanup, and leaves MCP transport/providers macOS-gated. |
| Listener stop/start currently controls global read lifecycle | TransitApp owns global lifetime; listener-instance admission tags allow scoped cancellation without closing native admission or resetting physical counts. |

Consensus: no requirement/scope/concurrency boundary blocker remains; narrow existing coordinator, retained publication, typed graph and owned save are appropriate. Peer review did not justify a second snapshot engine, persistence redesign, distributed fence or partial compensation. The 256-KiB event cap and retained-review/additive event decisions remain explicit design choices in the parent gate. The design has two runtime-dependent risks, each with early verification and stop/revise outcomes; no runtime proof or production promotion is implied.

Next gate is design approval only, then task planning. Requirements remain approved at the exact b1d02591 checkpoint; implementation/live bookkeeping/heavy runtime commands remain held.

## Design approval and task planning — 2026-10-05

Assistant Sentinel_ab83d2faaf308191a6733c2b51319d28 presented retained reviews, immutable same-store history, 256-KiB saved payload cap and guarded whole undo, explicitly saying approval moves to task planning and durability/budget behavior require implementation tests. Owner Sentinel_21b7c9588ec88191b7d78732649d99a9 replied “Approved”. Parent records exact design checkpoint 7714e30121baf55f51086924269bd253dc8bfd9b and Library packet libfile_31bf6900be6481919971a2a80d72763c. Both design ADRs and the payload limit are approved.

Task planning uses Starwave Tasks and Rune only. One implementation stream is required by shared coordinator/read/capture/schema/native integration and real dependency order. Heavy runtime work remains reserved to Meddy; task creation/parsing and internal document reviews do not run any implementation tests. No new human prerequisites, distributed fence, deployment or live bookkeeping task is introduced.

## Task review synthesis — 2026-10-05

Starwave Tasks and Rune produced twenty pending tasks in ten adjacent Red/Green pairs, all in stream 1. The first four tasks verify additive closed-store migration and the real owned group/history/receipt save before dependent integration. Tasks 7–10 verify complete evidence, shared lifecycle and full-envelope retention budgets before reviewed execution. Tasks 19–20 require real application construction and advertised registration, preventing fixture-only success or orphan components.

Design-critic reviewed first, followed by independent correctness and integration peers. All three found no blockers or required changes. Root independently validated Rune parsing/table rendering, twenty unique stable IDs, all twenty-eight acceptance criteria, adjacent pairs, one stream, connected valid dependencies and no cycles. Both approved design risks map to early paired tests with stop/revise outcomes. No source implementation or runtime validation was performed; future migration, durability and budget proof remains in the implementation tasks.

No new prerequisites or scope/design choices were introduced. Task approval completes planning only and does not authorize implementation or release heavy work reserved to Meddy. Live bookkeeping remains paused.

Next owner gate: “Do the tasks look good?” Separate implementation authorization is still required after task approval.

## Task approval and conditional implementation queue — 2026-10-05

Assistant Sentinel_08ad6eb332088191a0d9f0651b46f17e presented the twenty-task, one-stream plan covering all twenty-eight criteria with reviews clean, and asked: “Do you approve the tasks and authorise implementation when Meddy has released the test resources?” Owner Sentinel_30bf9cc075e48191997f3eaee84ba68d replied: “Approved. How is Meddy progressing?” This approval applies to task checkpoint 5921d7954304e4c5df34eca686f15fd7d89acb14 and Library packet libfile_fbcfd24510a88191b3fecffe6e61a9f3.

Parent instruction is to record this approval locally and remain queued until the parent confirms Meddy has released shared build/test resources. Implementation is authorised conditionally, with no further approval gate once that explicit resource-release confirmation arrives. Elapsed time, an idle worker, or an inferred resource state does not satisfy the condition. All twenty Rune tasks remain pending; no source changes, implementation launch or heavy checks have occurred. Live Transit bookkeeping remains paused.

Planning approval is complete. Current state: queued, awaiting parent resource-release confirmation.

## Implementation resource release — 2026-10-05

Parent thread 01a0f509-a620-77b6-be90-86178fbef00a explicitly confirmed Meddy completed local implementation, its owned build/test processes drained and its simulators shut down. The shared implementation/build/test slot is released to T2381. The conditional approval at 2f2254f0f3fb5efe5b2a7cd7e0dad385e2b3ec8e is satisfied. Work proceeds in one stream using synthetic stores, CloudKit disabled and isolated development test hosts; no live Transit fixture mutation.

## Phase 1 local durability foundations — 2026-10-05

Tasks 1–4 completed in stream 1 using isolated development hosts, owning fixtures and `cloudKitDatabase: .none`. The additive ninth entity stores defaulted/optional immutable scalar history without relationships, unique constraints or cascades. The bounded versioned codec rejects inconsistent participant/revision/accounting/occurrence evidence and preserves exact raw dates and metadata bytes. The existing protected coordinator now accepts the private group commands through sealed same-context services; no-save group changes, actual link tuples, staged participant revisions, immutable history and a terminal receipt share one save. Saved group receipts receive bounded participant/operation validation, and conflicts carry affected task UUIDs plus current r1 revisions rather than a fabricated single record.

The o1 token covers every immutable scalar event tuple, exact payload bytes and physical multiplicity. Opaque transient SwiftData PersistentIdentifier bytes are excluded from the content hash because they change on save; physical identity remains part of collision diagnostics. Tests prove staged/reopened o1 equality, ordering independence and multiplicity sensitivity. This follows the approved content-token contract and does not claim a distributed atomicity boundary.

Actual verification, with zero skipped tests and explicit nonzero discovery:

- Closed prior eight-entity store: four separate seed/legacy/upgrade/reopen runs, each 1/1 passed, distinct drained host processes. Raw task/comment/link/removal/receipt bytes remained preserved; upgrade/reopen show nine entities and no initial history rows. Evidence: `/tmp/t2381-phase1-unit/Build/Products/t2381-closed-{seed,legacy,upgrade,reopen}-drained.json`, corresponding `T2381Closed-*.xcresult`. This schema proof was not repeated for later owned-service-only changes.
- History/schema/codec final focused GREEN: 8/8 declarations, 12/12 expanded cases. Evidence: `/tmp/t2381-phase1-unit/Build/Products/T2381-foundation-green-evidence.json` and `.xcresult`.
- Owned group GREEN against the final refactor: 9/9 declarations, 16/16 expanded cases, including independent reopen, staged r1/o1 equality, five injected failure paths, two post-await draft paths, saved-response replay, participating request revalidation and three malformed saved terminal controls. Evidence: `/tmp/t2381-phase1-unit/Build/Products/T2381-owned-green3-evidence.json` and `.xcresult`.
- Existing coordinator receipt regressions: 6/6 passed against the final refactor. Evidence: `/tmp/t2381-phase1-unit/Build/Products/T2381-receipt-regression2-evidence.json` and `.xcresult`.
- Valid owned behavioral RED before routing: 8 declarations executed, 1 passed/7 failed, no crash/restart, drained host; `/tmp/t2381-phase1-unit/Build/Products/T2381-owned-red-full2-evidence.json`. Initial attempts with zero discovery and an earlier crashed RED were explicitly withdrawn and do not count as evidence. The first owned GREEN exposed three missing group receipt-validation paths; the corrected paired tests above pass.
- Final `build-for-testing` passed (`/tmp/t2381-owned-green-build4.log`); `make lint` passed ownership/source/configuration guards and strict SwiftLint with zero violations in 662 files (`/tmp/t2381-phase1-lint4.log`); Python helper AST parse and `git diff --check` passed. Test runners verified their owned hosts drained after every accepted final run.

The parent briefly reassigned the shared slot to the urgent Meddy fix, then explicitly returned it after installation and drainage. Automatic approval review twice misclassified the historical planning-only restriction despite recorded conditional implementation approval. No alternate route was used; exact preserved commands were retried once by the parent with owner approval evidence and accepted. The accepted actor fix resolved the compile error before final tests.

This phase establishes local fixture-backed durability. Production tool advertisement, complete planner/review lifecycle, native history, reversal execution and composed application wiring remain in tasks 5–20. Undo is explicitly unavailable in the phase-one service. Full iOS/unit/UI and pre-push review remain with the parent; no live Transit bookkeeping or production store was changed. Phase 1 is ready for the parent's review; the implementation worker stops after its phase commit.

## Phase 1 review corrections — 2026-10-05

The parent critic found two warranted defects in the local foundation: full before/after snapshots charged unchanged candidate content against the history payload cap, and reversal history only matched participants, allowing a forward apply relabeled as undo. Both are corrected before proceeding to task 5.

`TaskConsolidationReviewedTaskChange` retains full raw before/after values only in transient reviewed input. The owned service validates those raw values, checks them against current saved tasks, and requires their projected deltas to match the review's immutable payload. `TaskConsolidationTaskChange` saves only changed fields, each with explicit before/after values; JSON null means an actual null value and field omission means unchanged. Decode rejects missing delta endpoints, unchanged deltas, unknown fields, invalid status/date/metadata values. Actual commit-time status/date changes are projected to deltas before the pre-effect 256-KiB encoded-byte check and saved history.

Reversal history now requires the exact inverse changed fields by participant, no newly created occurrences, and `removedOccurrences` matching exactly the unique apply's created tuples. Retained occurrences must match exactly, including each tuple's multiplicity. This validates immutable imported history; executable undo remains task 14. The old non-expiry test now supplies a valid inverse instead of relabeling forward changes.

Paired behavioral RED executed 4/4 declarations with all four failing and no crash/restart (`T2381-review-fix-red-evidence.json`). Final focused GREEN on the corrected, lint-clean build executed:

- Review correction suite: 5/5 declarations, 10/10 expanded cases. Covers 600-KB unchanged input with a small history payload, exact changed-field cap/null handling, relabeled forward undo, disagreeing inverse fields/removals/retention/multiplicity, and malformed delta endpoints/unknown/unchanged fields.
- Existing history/schema/codec controls: 8/8 declarations, 12/12 expanded cases.
- Real owned commitment suite: 10/10 declarations, 18/18 expanded cases. Adds actual large unchanged candidate preservation and stale transient raw-review rejection; existing one-save/reopen/r1/o1/receipt/fault controls remain green.

All final runs had zero failures/skips, enforced nonzero discovery, and drained their owned test hosts. Evidence is under `/tmp/t2381-phase1-unit/Build/Products/T2381-{review-fix-green2,foundation-green2,owned-green4}-evidence.json` and corresponding `.xcresult` bundles. Final build passed (`/tmp/t2381-review-fix-green-build3.log`), strict `make lint` passed guards and zero violations in 664 Swift files (`/tmp/t2381-review-fix-lint4.log`), Python helper AST parse and `git diff --check` passed. Scalar/schema registrations are unchanged; the earlier four-stage closed migration proof remains applicable and was not repeated. Tasks 1–4 retain completed status on this corrected proof. No live store, advertised production tool, CHANGELOG or parent-owned review artifact was changed.

## Phase 1 review acceptance and integration handoff — 2026-10-05

Implementation checkpoint b1e9e4c481394839a8e5ba9980950280c58c0f74 established the durability foundation. The phase critic found unnecessary unchanged raw-field history copies and insufficient inverse-history validation; correction checkpoint 2e2a78157fffe418b8bc6bceee8bd602c45821cd fixes both with paired regressions. Critic recheck confirmed both findings resolved, no remaining phase-one blocker, and recorded final 5/10 correction, 8/12 foundation and 10/18 owned declarations/cases passed with zero skips and drained hosts.

Root verified clean worktree and Rune four completed tasks. One available stream remains for tasks 5–20. The approved shared slot is available; the same implementation worker proceeds through the second phase. Final platform verification, pre-push review and PR workflow follow; no new merge authorisation is inferred and live bookkeeping remains paused.

### 2026-10-05 — Value planner and history assessment (tasks 5–6)

The pure planner binds selected physical task/project identities, exact raw fields, comments/link-covered r1 and caller accounting to one combined graph proposal. Survivor edits preserve omission versus explicit null; unfinished candidates alone close at the later owned commit time. The history projection retains readable immutable evidence when current participant revisions or graph evidence prevent reversal. Its plan adapter is exercised through the existing owned coordinator, without production advertisement.

The behavior RED run discovered 5 declarations / 13 expanded cases: 9 invalid-input cases passed and all four positive declarations failed against the throwing planner stub. GREEN discovered and passed 6 declarations / 14 expanded cases, zero skips, including the actual owned-service consumer. Both guarded runners recorded owned process drain. Exact artifacts: `/tmp/t2381-phase1-unit/Build/Products/T2381-planner-{red,green}-evidence.json`; GREEN build `/tmp/t2381-planner-green-build3.log`. Strict lint passed after formatting corrections: `/tmp/t2381-planner-lint-final3.log`. Closed migration was not repeated because scalar/schema/codec definitions were unchanged.
