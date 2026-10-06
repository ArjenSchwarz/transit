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

### 2026-10-05 — Complete saved closure and shared read ownership (tasks 7–8)

The existing history/generation watermark was extracted into `SavedReadBoundary`, with the ninth event entity included in its proof of an empty store. MCP full captures and native consolidation support use that same boundary; production has no actor-only fallback. Scalar participant queries identify relevant operations, followed by complete exact operation-ID lookup. Imported physical multiplicity is preserved and malformed history is rejected before availability assessment. Supplementary participant/comment/incidence/canonical-path originals stay separate from query selection. Payload/comment sizes are charged while copying, and the complete encoded evidence plus retained graph backing is bounded before return. Fresh full records advertise complete history coverage; legacy captures with absent coverage remain unchanged.

TransitApp owns one Foundation coordinator across platforms. Native Codable value reads and listener reads use the same eight unfinished physical slots and original deadline. Listener stop/replacement invalidates only that listener's entries; whole-application stop retains its prior global semantics. Cancelled/timed-out workers retain capacity through physical cleanup. The existing domain, publication gates and diagnostic queue are reused; the diagnostics lock now uses the standard library instead of a macOS-only transport dependency.

PersistentIdentifier values must be compared after decoding or encoded canonically: independently encoded JSON key order caused an initial current-undo assessment mismatch. Originals now bind to the uniquely resolved graph physical key, and project keys use sorted encoding. Generic r1 and historic page bytes were not changed.

Valid RED: 8 declarations / 8 executed cases, 5 guards passed and 3 positive behaviors failed against unavailable capture/global listener-stop stubs. Final GREEN: 14 declarations / 14 cases passed, zero skips. Existing coordinator/diagnostics/typed-link capture regressions: 19 declarations / 20 expanded cases passed, zero skips. Both final guarded runners confirmed owned process drain. Evidence: `/tmp/t2381-phase1-unit/Build/Products/T2381-capture-{red2,green5}-evidence.json` and `T2381-read-lifecycle-regression-evidence.json`; final build `/tmp/t2381-capture-green-build7.log`; final strict lint `/tmp/t2381-capture-lint-final.log` passed.

Intermediate GREEN runs are not completion evidence: `capture-green` passed 7/8 with the physical-key mismatch, and `capture-green4` passed 13/14 because its test used unsupported full-query arguments. Compile-only fixture/signature/actor-isolation failures were corrected normally. Their preserved logs/results remain diagnostic artifacts. Closed migration was not repeated because schema, scalar types and codec were unchanged. iOS runtime/full platform suites remain the final integration checks, rather than a claim from this focused macOS pair.

### 2026-10-06 — retained preview checkpoint during shared resource hold

Task 9 is in progress. The signed isolated host compiled after correcting the
retention fixture's established MCPResultContext labels. Guarded retention RED
executed four declarations: zero passed, four expected failures; process drain
was verified. Evidence: `/private/tmp/t2381-phase1-unit/Build/Products/T2381-preview-retention-red-evidence.json`.
The additional complete preview input/readback stubs compile in
`/tmp/t2381-preview-red-build.log` (exit 0), but their behavioral RED has **not**
run. They remain stubs; no GREEN or task completion is claimed.

Using the verified retention RED only, source now adds immutable ordinary review
roots, exact scope/kind/p1 lookup, five-minute expiry without extension, shared
eight-root capacity, complete prepared wrapper plus proposal/index backing
charges, and carry/retirement across ordinary index rebuilds. Lookup validates
review identity directly under the existing publication domain; legacy page
pins continue requiring their original retained page. These source changes
are **uncompiled and untested** at this checkpoint. No commit or lint was run.

Asterism's phone/iPad acceptance pipeline owns the shared heavy slot. New
builds/tests/lint are paused until that slot returns; all pending work remains
in this checkout. Next: run the additional preview RED, then verify the retention
source and implement the remaining preview adapters. Also cover the discovered
MCPReadService metadata-freezing reconstruction that drops consolidationEvidence.

### 2026-10-06 — verified retention and aggregate-capture correction checkpoint

The parent authorized a bounded retention/capture checkpoint before returning the
shared slot to Meddy validation. Task 9 remains in progress and task 10 pending;
this commit does not claim complete preview adapters or advertised capabilities.

Ordinary review roots now use the existing response-gated reservation, exact
reviewId/p1/kind/local-scope lookup, five-minute expiry without consumption or
extension, shared eight-root capacity and complete prepared response plus
proposal/index backing charges. Every ordinary index replacement carries or
retires review entries with descriptor roots; legacy page-pin requirements remain
unchanged. These four behaviors were RED (4 declarations, 4 expected failures)
and are included in final GREEN below.

The confirmed aggregate capture finding is corrected: one charge tracks graph,
events, originals and history projections; values are rejected before append and
large encodes have checkpoints. The exact final wrapper remains the publication
limit. A six-original regression proves each individual value fits but collection
stops before fetching all six when the group exceeds its budget. Review then
found a false lower-bound rejection for whitespace-heavy metadata: raw metadata
appears once, while the public record stores decoded metadata. This was
reproduced RED (2 declarations/cases, 1 pass and 1 expected failure), corrected by
counting raw metadata once, and verified to preserve exact raw bytes at the
measured complete-wrapper budget. The final read-only critic found both capture
budget findings resolved, with no residual bounded blocker.

Final focused GREEN: **20 declarations / 20 executed cases, all passed, zero
skipped**, with guarded host preflight and owned processes drained. Suites:
ReviewRetentionTests (4), ConsolidationCaptureAggregateTests (2),
TaskConsolidationCaptureTests (10), TaskConsolidationReadLifecycleTests (4).
Evidence: `/private/tmp/t2381-phase1-unit/Build/Products/T2381-retention-budget-green2-evidence.json`.
Build: `/tmp/t2381-retention-budget-green2-build.log` (exit 0). Strict repository
lint: `/tmp/t2381-retention-budget-lint-final.log` (exit 0; 686 files, zero
violations). Closed migration was not repeated because the schema/codec was
unchanged. No live Transit or production app mutation occurred.

Larger preview work remains preserved and uncommitted. Its earlier expanded RED
artifact executed 14 declarations (8 pass / 6 fail; 21 expanded cases) but included
invalid no-effect assertions comparing opaque PID JSON byte order; it is
diagnostic rather than complete preview proof. Pending tests now compare decoded
PersistentIdentifier equality while retaining exact raw task/date/metadata,
record/comment bytes, revisions and counters. Complete adapters, saved metadata
evidence forwarding, additional publication/cancellation tests and fresh preview
RED/GREEN remain required before tasks 9–10 can complete.


### 2026-10-06 — Tasks 9–10 retained previews verified

The isolated signed development host uses synthetic fixtures and CloudKit.none. The shared slot was returned after Meddy drained; existing direct implementation/build/test/commit authorization remains in force. Production advertisement remains reserved for task 20. The injected handler alone exposes the private preview adapters in these tests.

Apply and undo previews now resolve selected groups or operation participants inside the existing saved capture boundary, carry supplementary history through metadata freezing, and retain immutable typed input, full originals, complete graph/event closure and planned deltas. Complete modern wrapper owners and proposal bytes share ordinary retention accounting; response selection alone publishes the review root. Scope/kind/p1, fixed five-minute root expiry, clear/rebuild, capacity, original deadline, cancellation and actual outer encoding faults have no domain effects. Canonical p1 preserves candidate order and exact saved raw fields/dates/payloads while normalizing opaque physical-identity JSON and unordered saved enumeration.

Two parent critic findings were resolved with behavioral RED/GREEN: every original now includes saved direct/canonical link assessments, including a multi-hop duplicate chain; projection, apply/reversal planners and proposal preparation receive the original request cutoff/checkpoint. Parent critic recheck accepted both fixes without a residual bounded blocker.

Broader existing capture regressions exposed a borrowed-comment fault being reset by supplementary saved refetch and unnecessary full-body recopying when no relevant history exists. Comment evidence is frozen before refetch. Supplementary originals are captured only for affected operation participants/canonical closure unless the request explicitly requires selected originals; selected scope/full ordinary records/comments remain complete. A saved empty-event-store proof avoids per-participant queries in the empty case. The unchanged 2,375-task provider benchmark succeeds without extending any budget: physical capture 3.771954917 seconds, frozen record encoding 0.007823042 seconds, 1,580,090 bytes.

Evidence (all guarded commands require exact nonzero discovery and reject skips; owned host/build processes drained):
- Canonical RED: 19 declarations, 18 passed / 1 expected failure, `/private/tmp/t2381-phase1-unit/Build/Products/T2381-preview-canonical-red-evidence.json`.
- Canonical GREEN: 19 declarations / 26 expanded cases passed, `/private/tmp/t2381-phase1-unit/Build/Products/T2381-preview-canonical-green-evidence.json`.
- Critic RED: 21 declarations, 19 passed / 2 expected failures, `/private/tmp/t2381-phase1-unit/Build/Products/T2381-preview-critic-red-evidence.json`.
- Critic GREEN: 21 declarations / 28 expanded cases passed, `/private/tmp/t2381-phase1-unit/Build/Products/T2381-preview-critic-green-evidence.json`.
- Empty-history RED: 3 declarations, 2 passed / 1 expected failure, `/private/tmp/t2381-phase1-unit/Build/Products/T2381-capture-empty-red-evidence.json`.
- Final GREEN: **45 declarations / 52 expanded cases passed, zero failures/skips**, `/private/tmp/t2381-phase1-unit/Build/Products/T2381-preview-final-green2-evidence.json`; result bundle `T2381-preview-final-green2.xcresult` in that directory. Build `/tmp/t2381-preview-final-green2-build.log` exited 0.
- Required lint `/tmp/t2381-preview-pair-lint-verified.log` exited 0: 688 files, zero violations.

Diagnostic runs are not passing evidence. The first integrated GREEN attempt ran 18 declarations / 25 cases with one failing assertion that treated a query-task selector outcome as its task. That assertion is withdrawn; the corrected test requires `outcome.task` and passes in the final inventory. An earlier encoder fault test did not require its callback to execute; final proof requires exactly one callback with one unpublished pending review. The first broader final run executed 44 declarations / 51 cases with two failures; both are resolved in the final 45-declaration run above. Tasks 9–10 are complete; retained-review apply/undo execution and advertised production wiring remain subsequent tasks. No schema change, migration rerun, live mutation or production launch occurred.

### 2026-10-06 — Source continuation while heavy verification is held

The user explicitly corrected the resource policy: source implementation can continue while only builds/tests need an isolated environment. Direct implementation authorization remains in force. Tasks 11–20 have source drafts covering retained apply authority, whole inverse/reconciliation, staged mappings, strict four-tool schemas and capability gating, pre-save complete response representation charging, shared-coordinator native history/state, unique saved original/canonical navigation and application-owner wiring. Task 11 is in progress; no task beyond 10 is declared complete.

Bounded read-only reviews accepted retained apply authority and whole-undo checks. Wiring review found missing macOS detail-window environment injection, two static routing identifier references, unconstrained nested schema placeholders and missing original participant navigation. These source defects are corrected. The earlier claim that the shared helper already injected the reader was inaccurate: the first edit reached only the main scene; the actual helper was subsequently corrected. No compile or runtime success is inferred from review.

Unexecuted RED source snapshots and full draft preservation are under `/tmp/t2381-source-checkpoints/`, including `11-apply-red-corrected`, `13-undo-red`, `15-wire-red-source`, `17-native-red-source`, `19-app-wiring-red-source`, `20-contract-red-source` and `11-20-source-ready-unverified`. The snapshots exclude root-owned `CLAUDE.md` and `CHANGELOG.md`. The queued serial commands and exact fresh evidence targets are `/tmp/t2381-source-verification-queue.json`. Expected source inventories are apply 4 declarations/13 expanded cases, undo 4/8, and composed 20/38; actual discovery and execution remain pending. Native UI has one additional drafted declaration, whose platform/configuration expansion must be measured from compiled inventory.

No new builds, tests, lint, production launches, live Transit writes or heavy processes were started during this source continuation. Existing verified evidence remains the c16cea0 preview checkpoint (45 declarations/52 cases, zero skips, drained). Required focused/platform verification, lint and subsequent implementation commits remain pending the shared slot release.

### 2026-10-06 — Protected execution and composed source milestone

The exclusive heavy slot returned; direct user build/test/commit authorization applies. Retained apply and whole inverse now run against fresh owned saved evidence through the existing coordinator. Actual staged occurrence identities, raw restored values, participant r1s, mappings and inserted history o1s feed one final event/effects/receipt save. The four strict contracts and native history reader use the application-owned coordinator; modern uncertainty preselects compact original tool/key recovery bytes and retains a known undo operation identity. No new persistence engine, all-writer fence, native mutation UI or live activation is introduced.

A mandatory parent critic found p1 comparing unrelated full-graph names/statuses. Its valid RED executed 10 declarations / 25 expanded cases (8 declarations / 21 cases passed; 2 declarations / 4 expected cases failed), artifact `T2381-phase2-authority-red-evidence.json` in `/private/tmp/t2381-phase1-unit/Build/Products/`. Authority now covers typed input, exact raw originals/r1/event evidence, reviewed deltas, required canonical/incident physical evidence and dependency endpoint statuses. The complete bounded backing has a separately charged integrity digest; full fresh graph planning still runs before authority comparison. Unrelated graph names/statuses no longer invalidate a valid review. Parent critic recheck accepted this correction. Authority GREEN: 11 declarations / 26 cases, all passed, zero skips, drained, `T2381-phase2-authority-green-evidence.json` in the same directory.

Composed focused GREEN: **31 declarations / 51 expanded cases, all passed, zero skips, drained**, `T2381-phase2-composed-green2-evidence.json` and matching xcresult in that directory. Build `/tmp/t2381-phase2-composed-green4-build.log` exited 0. Coverage includes six-ticket mixed-status accounting/retained chains, exact raw whole undo, current review conflicts, old-key replay, strict nested schemas and malformed imported terminals, pre-save full-wrapper limits, shared native admission/state, modern participant references and post-commit encoding uncertainty including known undo identity.

Withdrawn diagnostic runs remain preserved. The first undo run incorrectly assumed no earlier retained root and ignored pre-existing removal evidence. The first composed run executed 28 declarations / 48 cases with one failing six-ticket fixture whose duplicate chain ended at another candidate; the fixture now ends at the actual survivor and the production canonical rule remains strict. Compile failures from missing test try/nested require and lint argument extraction were corrected; they are not runtime proof. Draft RED snapshots created while the heavy slot was held remain source-only, not executed RED evidence.

Tasks 11–16 may complete against focused proof and shared foundation fault/reopen controls. Native layout UI and full current macOS/iOS/unit/UI inventories remain pending; tasks 17–20 are not claimed complete in this source milestone. Root-owned CLAUDE.md and CHANGELOG.md remain outside this commit. Final guarded runners are prepared under `/tmp/t2381-final-verification/`; no full-suite result is inferred from compilation or source review.

Milestone lint `/tmp/t2381-phase2-milestone-lint3.log` exited 0: 711 files, zero violations. `git diff --check` passed. The compact recovery helper extraction is structural; the following full macOS build/suite will verify its compiled placement.

### 2026-10-06 — Final source critic receipt-kind correction

The complete phase-two critic found that a prelinked apply with no new occurrences could accept an imported terminal whose history.apply payload was relabeled to the known undo kind. A dedicated test first validates the real committed receipt, requires zero created occurrences, then relabels only kind. Valid RED: 3 declarations / 6 cases (2 declarations / 5 cases passed, 1 expected failure), zero skips/drained, `/private/tmp/t2381-phase1-unit/Build/Products/T2381-receipt-kind-red-evidence.json`. The common history validator now explicitly requires history.apply.kind == apply for all group terminals. GREEN: all 3 declarations / 6 cases passed, zero skips/drained, matching `T2381-receipt-kind-green-evidence.json`. Build `/tmp/t2381-phase2-receipt-kind-green-build.log` exited 0. Parent source critic recheck accepted the correction and found no remaining mandatory source issue.

The extracted pure compact recovery helper explicitly declares nonisolated under the project's default MainActor setting. Its preceding failed placement build is retained at `/tmp/t2381-phase2-final-macos-build.log`; corrected build2 exited 0. Native UI source now also requires the Applied state and actual retained preservation explanation before exact original navigation. This rendered UI behavior is still pending execution. Strict lint `/tmp/t2381-phase2-receipt-kind-lint.log` exited 0: 711 files, zero violations. Full platform checks remain pending.

### 2026-10-06 — Final review corrections and focused compatibility proof

The first complete macOS run is diagnostic, not passing evidence: 2,629 declarations (2,617 passed, six failed, six intentional opt-in skips), with 3,402 passed / eight failed / six skipped expanded cases. The retained result is `/private/tmp/t2381-phase1-unit/Build/Products/T2381FinalMacOS.xcresult`; guarded runner evidence is `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/t2381-final-macos.9vzpzmsz`. The host drained. Three genuine compatibility corrections restore stopped-listener admission precedence, deliberately absent graph handling for empty ordinary reads, and ordinary value freezing before supplementary saved refetch. Three fixture corrections compare decoded physical identity, UUID-keyed revisions, and an exact graph-byte accounting delta while keeping supplementary backing constant. The read-only compatibility critic accepted these corrections. Focused compatibility GREEN executed 60 declarations / 102 cases, zero failures/skips, with drained evidence `T2381-full-suite-corrections-green-evidence.json` in the products directory.

Final mandatory reviews found imported participant effects outside the apply contract, missing identity/error diagnostics, repeated participant queries/history filtering, and missing rendered negative/reversed UI coverage. Imported apply now permits only survivor description/metadata changes and unfinished candidate abandonment/status dates. Changed completion dates cannot become null; two present commit-date deltas must agree. Omitted dates remain valid. All imported decode/validation failures normalize to typed malformed history while preserving capacity/version errors. A real handler preview and retained owned undo reject forged imported candidate-description history without domain/history/link/comment/removal effects; preview adds no receipt, accepted owned rejection adds exactly one terminal receipt. Selection errors include bounded UUID/reason diagnostics; review and history unavailable codes are distinct and registered in modern classification, preserving authoritative follow-source rejection recovery. Saved participant discovery uses 128-ID chunks with nil excluded from candidate membership; complete operation-ID closure and physical multiplicity remain intact. One bounded operation index replaces repeated full-event filters. Saved synthetic rendered fixtures cover reversed, unavailable, over-limit, missing and ambiguous original references, but rendered runtime proof is still pending.

The initial new focused run discovered 43 declarations / 81 cases and failed three declarations / seven cases. These were fixture routing/recovery assumptions: the old preview fixture returns a literal rejection on thrown errors, whereas the actual handler prepares diagnostic JSON; established recovery is `follow_source`, with source `new_request_new_key`. Tests now exercise the actual composed handler and exact recovery source. That failed result remains `T2381-final-review-corrections-green.xcresult`; it is withdrawn as GREEN evidence. Compiler-only failures in builds 1–2 involved a qualified fixture Comment type, a synthetic optional project unwrap, and predicate type-check complexity; the equivalent membership predicate is split into two composed expressions.

Final exact-source focused GREEN: **43 declarations / 81 expanded cases passed, zero failures/skips, owned host drained**, `/private/tmp/t2381-phase1-unit/Build/Products/T2381-final-review-corrections-green3-evidence.json`. Build `/tmp/t2381-final-review-corrections-build5.log` exited 0. Required strict lint `/tmp/t2381-final-review-corrections-lint4.log` exited 0: **719 files, zero violations**. All four final source review roles accepted the bounded corrections. Structural helper extractions retain the verified contracts without lint suppressions. Full corrected macOS/iOS and rendered macOS/iPhone/iPad gates are pending; tasks 17–20 are not declared complete from compile/focused evidence alone. No schema change, closed-store migration rerun, live write or production activation occurred.

### 2026-10-06 — Retired-reference admission compatibility

The second complete macOS attempt ran 2,636 declarations: 2,629 passed, one failed, six intentional opt-in skips; expanded cases were 3,430 passed / one failed / six skipped. `T2381FinalMacOS2.xcresult` and `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/t2381-final-macos.r2je0bk3` retain this diagnostic failure; host drainage was proved. The unchanged portfolio lifecycle regression showed that the new stopped-listener guard masked invalid retired snapshot/cursor errors. The guard now exempts only retained references for query_tasks/query_project_summaries. Existing strict parsers and invalidated no-capture lookups preserve original diagnostics without renewal/publication; fresh covered reads still return READ_BUSY before unavailable service/capture, and native admission remains independent. The read-only critic accepted the narrow precedence correction, with no test expectation changes.

Focused GREEN: 15 declarations / 19 cases passed, zero failures/skips, drained, `/private/tmp/t2381-phase1-unit/Build/Products/T2381-retained-lifecycle-green-evidence.json`. Build `/tmp/t2381-retained-lifecycle-build.log` exited 0; strict lint `/tmp/t2381-retained-lifecycle-lint.log` exited 0 with 719 files / zero violations. The corrected full macOS/native/iOS queue remains pending.

### 2026-10-06 — Full macOS pass and corrected platform startup

The complete macOS target passed at source `484dd2c`: 2,636 discovered declarations, 2,630 passed / zero failed / six exact intentional opt-in skips; expanded cases 3,431 passed / zero failed / six skipped. `/private/tmp/t2381-phase1-unit/Build/Products/T2381FinalMacOS3.xcresult` and `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/t2381-final-macos.nac7sajm` retain compiled inventory, summaries, exact skip IDs and successful host-drain evidence. Skips are the two closed-store stage entry points, two primitive transaction diagnostics, development schema verification and the outside-writer boundary counterexample; their dedicated opt-in prerequisites are not supplied by a general suite run.

Rendered macOS verification is environment-blocked, not passing: native enumeration and run both failed XCTest UI initialization with `Timed out while enabling automation mode.` No consolidation UI declaration executed; the harness reports its own runner failure. `/private/tmp/t2381-phase1-unit/Build/Products/T2381NativeMacOS.xcresult` and `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/t2381-native-macos.se9gbpbx` preserve the failure and both successful process-drain records. Parent read-only diagnosis found console owner arjen and DevToolsSecurity developer mode disabled, a concrete prerequisite candidate rather than a proven sole cause. No global security/TCC/settings mutation or relaxed discovery occurred. A safe future retry requires an authorized working interactive XCTest automation environment, fresh result paths and valid four-declaration discovery before execution.

The initial fresh iOS build correctly rejected AppDelegate access before the new immutable reader/coordinator owners initialized. Its simulator was shut down/deleted, with remaining processes empty; diagnostic log is `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/t2381-final-ios.mtd7uuvp/build.log`. Shared reader/coordinator construction now precedes the iOS AppDelegate access, preserving one app-lifetime owner and all native/MCP injection paths. The read-only critic accepted the reorder. Corrected iOS build `/tmp/t2381-ios-initialization-build.log` and corrected Mac startup build `/tmp/t2381-platform-startup-macos-build.log` both exited 0. New-source Mac factory/native-state/lifecycle/end-to-end focused proof passed **12 declarations / 12 cases, zero skips, host drained**, `T2381-platform-startup-green-evidence.json` in the products directory. This focused new-source verification supplements the previous full macOS source proof; it is not a blanket old-head result claim. Strict lint `/tmp/t2381-ios-initialization-lint.log` passed with 719 files / zero violations. Fresh iPhone full unit/UI and iPad rendered checks remain queued; tasks 17–20 remain pending until required gates are satisfied.


### 2026-10-07 — rendered Form navigation correction (verification pending)

The bounded full iPhone UI attempt discovered all 27 declarations, then timed out at 1200 seconds; its raw result is unfinalized and no full-suite pass is claimed. Three consolidation negative/reversed declarations passed. The applied/accounting/navigation declaration failed on Applied before its intended original-task navigation. An owned simulator screenshot shows History Original detail at that boundary, confirming unintended navigation from the disclosure-header tap. Destination buttons inside the Form now use borderless style to prevent row-wide automatic actions. All existing exact state/accounting/navigation assertions remain unchanged. Fresh focused phone/iPad proof and lint remain pending. The failed attempt simulator was shut down/deleted with no remaining owned hosts.
