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


The fresh four-declaration iPhone run finalized 3 passed/1 failed/0 skipped (exit65, no timeout); all owned hosts drained and its simulator was deleted. The history-destination-only style was insufficient and is not claimed GREEN. Exported native hierarchy and recording frame before the actual header tap show T-1 with collapsed reason header; the recorded tap coordinate is (201,849.5), on that header. TaskDetailView places TaskLinksSection and history inside one Form-row VStack; the existing TaskLinksSection automatic destination button still intercepts row taps. Borderless style now scopes the shared relationships row, leaving UUID resolution and all exact state/accounting/navigation assertions unchanged. Fresh proof is pending.


The next six-test iPhone attempt executed five passed/one failed per native log (both existing relationship controls passed), then hit its 1200s limit during result finalization. No finalized counts are claimed; final drain and simulator deletion succeeded. Applied now passes while retaining T-1. Accounting selection rematches the inherited consolidation.operation identifier and collapses the outer disclosure; the failure screenshot confirms collapsed T-1. Removed the group-wide identifier and assigned unique operation-scoped reason/accounting/payload/state leaves plus role/target-scoped destination controls. Exact UI text/accounting/navigation assertions remain and label equality assertions are added. Local xcodebuild -help documents -collect-test-diagnostics never as omission of verbose failure diagnostics; runner-only use preserves test declarations/assertions/rendering and ordinary XCTest failure attachments. Fresh proof remains pending.


The distinct-control run finalized six declarations/cases, five passed/one failed/zero skipped (exit65, no timeout); both existing relationship controls passed and all owned hosts/simulator drained/deleted. Its exported accounting tap is (201,260.5); the saved frame at20s shows that exact coordinate on Preservation accounting while outer reason is expanded and Applied visible. Correct accounting tap collapses the outer history, so identifier collision was not the remaining cause. A small DisclosureGroupStyle scoped only to consolidation history now uses independent borderless header buttons toggling each configuration.isExpanded, with the same labels/content and accessible expanded state. Domain/navigation/reader behavior and exact UI assertions remain unchanged. Critical one-scenario proof precedes remaining three history declarations/iPad four; if it remains red, retain the residual blocker rather than repeat a long suite.


## Final native handoff — 2026-10-06

Source remains `a1829161885a009b99b636e254d8475f44cddd8d`. Current signed iOS/macOS builds exit 0 and strict lint passes 719 files / zero violations. Full-unit evidence remains source-qualified: macOS at `484dd2c` passes 2,630 declarations / 3,431 expanded cases, six exact intentional opt-in skips; iPhone at `ffbf62cf` passes 1,351 declarations / 1,455 expanded cases, zero skips. The separate four-host closed eight-to-nine entity migration proof remains valid; the history model schema has not changed. No blanket final-head full-suite result is inferred from view-only corrections.

At `a182916`, four phone history declarations pass across disjoint one-test and three-test runs, zero failures/skips. The exact Applied state, retained explanation, original name/UUID/navigation and destination history assertions pass. The remaining declarations cover reversed, unavailable, over-limit, missing and ambiguous fixture states. The two existing relationship controls passed at the earlier `c4488acc`; their source attribution remains explicit. Each focused run has finalized xcresult counts, host drainage and owned simulator deletion.

The iPad run is finalized: four declarations/cases, three passed, one failed, zero skips; xcodebuild exits 65 and all owned hosts/simulator are drained/deleted. Applied and exact reason/accounting labels pass, but the retained-explanation assertion at `TaskConsolidationNativeUITests.swift:29` fails before intended original navigation. Recorded accounting tap at t31.64 is followed by a second survivor navigation at frame33; the first reveal swipe starts later at t35.40. The underlying hit-frame/gesture mechanism remains unresolved. Preserved recording, frames, tap coordinate and result paths are in `verification-handoff.json`; no speculative source correction or further UI run was started.

macOS UI still executes zero feature declarations because XCTest automation initialization times out. Read-only developer-mode status is a prerequisite candidate, not a proven sole cause; no machine-wide permission/security/TCC changes occurred. The earlier bounded full 27-declaration phone UI attempt remains incomplete with an unfinalized raw result. Tasks 17–20 are open and the feature is not Done. All old failed attempts remain recorded, including finalized failed focused runs; passing focused phone evidence does not relabel them.

The heavy slot and index are released; no owned build/test job remains. Parent may proceed with Meddy tooling/warning checks and Asterism acceptance. Only local documentation/review-artifact and already-authorized draft-PR bookkeeping remain. Live Transit status/comments, production CloudKit activation, installation, deployment and merge are paused/outside scope. The new native record introduces no additional implementation or spec approval gate; future native execution must be coordinated with the parent's heavy queue.


## Source review continuation — 2026-10-06

After the native handoff, implementation continued while Meddy owned the heavy slot. Four source files now contain an uncommitted, uncompiled and unexecuted checkpoint on top of documentation commit `66f5bd5e8235b2832e343ef510d0cf98eea1c545`. Earlier build, lint and runtime evidence remains attributed to its recorded source; it does not verify these changes.

The history-only repair hypothesis changes explicit disclosure and destination buttons from borderless to plain, retaining destination tint. Exact iPad frames at 31.8/32.0 seconds place the recorded accounting tap on its visible header; navigation starts before the subsequent reveal swipe. The prior estimate that the tap overlapped a survivor destination was incorrect. No helper defect explains that old failure, and the underlying hit/gesture mechanism remains unproven.

Local review of tasks 17–20 identified and addressed missing composed coverage: deterministic same-source refresh bursts, rendered saved field changes and recorded canonical references, advertised tools, public participant history after apply/undo, retained-page logical content, unselected records/links, and composed stale, pending-draft and capacity cases. The pending-draft case preserves the existing truthful uncertain outcome while checking zero fixture domain effects. Source review does not establish runtime success or complete these tasks.

Read-only Mac diagnostics show both runner attempts timing out while enabling XCTest automation, before any feature test or app launch. Runner and app paths/bundle identifiers match the xctestrun metadata. Developer mode is disabled, a prerequisite candidate rather than a proven sole cause. No machine-wide setting was changed; this is an environment/harness initialization limitation, not evidence of a history code failure.

The smallest requested verification batch is guarded signed test builds and strict lint, then NativeState/EndToEnd focused units (expected nine declarations/ten expanded cases, subject to actual discovery), then the single critical iPad history declaration. Only if that passes should the remaining three iPad history declarations and four phone history declarations follow. Every run requires exact discovery, finalized results and owned host/simulator cleanup. No job starts before the parent grants a heavy slot. The incomplete full phone UI gate and Mac automation environment remain separate acceptance work.

Live CloudKit proof is not a blocking requirement: approved task 19 explicitly excludes a live service/CloudKit fixture, and task 20 excludes production promotion and client activation. The separate successful local closed-store migration proof remains preserved. Tasks 17–20 stay open; draft PR 255 remains at the earlier verified handoff, with no new push in this continuation.


## Bounded verification checkpoint — 2026-10-06

The reviewed source is saved locally in `6f36b782bb994d4a88753f929974a0a173a38e62`. Signed iOS and macOS test builds pass; strict lint passes 719 files with zero violations. The first lint attempt's parameter-alignment failure remains preserved. The new UI test explicitly selects the first of two identical recorded canonical references while retaining its exact name/UUID assertion; this selector correction and bounded reverse traversal introduce no production navigation change.

Focused NativeState/EndToEnd discovery reached its 120-second bound without producing a compiled inventory, launching a development host or executing a test. Nine declarations/ten expanded cases remain expectations, not discovered or passed counts. The bounded runner exits 1 after owned cleanup; xcodebuild's destination-only log, interrupted raw result, command and process sample are preserved. The cause is unproven and must not be equated with the older Mac UI automation initialization failure. No blind retry or machine-wide permission change occurred.

The critical iPad test and subsequent iPad/phone tests were not started because the unit gate remained incomplete. The plain-button repair remains a runtime-unverified hypothesis; the earlier finalized iPad failure remains open. Prior full units and focused phone evidence retain their original source attribution. Tasks 17–20 and full phone UI/Mac UI acceptance remain open; no new completion or live CloudKit gate is introduced.

All owned build/test processes drained; no simulator was created in this batch. The heavy slot and index are released for Asterism final acceptance. Source changes are committed locally; the existing draft PR stays at `66f5bd5` because this checkpoint has not been pushed. Actual evidence and cleanup are in `/tmp/t2381-plain-consumer-batch/checkpoint.json`; repository `verification-handoff.json` preserves this batch alongside all earlier proof.


## iOS history row repair — 2026-10-07

On the unchanged signed source `6f36b782`, the user-approved normal Xcode CLI route restores both synthetic sentinels, the three explicit isolation inputs and test-bundle startup. The first stripped-method selector finalizes with zero execution and is rejected. Preserving the exact Swift Testing method signature, including parentheses, then passes the exact 1/1 probe and focused nine declarations/ten expanded cases with zero failures/skips and owned host drainage. The same-source comparison identifies the bespoke controller wrapper as the practical launch incompatibility; the exact internal Xcode API remains unproven. The controller wrapper's additional OS network/production/group-file denials were omitted only after the user approved the disclosed protection difference. Tool sandbox policy and Mac security settings were not changed. Existing signed development identity, entitlement exclusions and delivered startup preconditions remain.

The critical iPad case at that source finalizes with one failure, zero skips and exit 65: Applied is visible, then the exact accounting-header tap collapses the outer history and the Expanded value assertion cannot find its control. The fresh owned simulator is shut down/deleted and every owned job drains; remaining iPad scenarios are not run after that failure. Older phone passes and full-unit proofs remain attributed to their original sources.

This source-only repair renders iOS reason, accounting, changes and destinations as sibling Form rows with independently keyed expansion state. It removes the shared iOS relationships VStack and nested history DisclosureGroups. Payloads, status/date formatting, recorded paths, unique navigation resolution, accessibility labels/values and all existing assertions are preserved. macOS retains its existing VStack/disclosure layout. Review identified a heading-row lifetime hazard, so the single observable refresh owner, task and save/remote-change subscriptions now live on the stable TaskDetailView ancestor rather than a lazy Form row; unresolved navigation requests that same owner's refresh.

The repair has source review and whitespace checks only; it has not been compiled, linted or run. T2404 owns the heavy slot. Next-slot verification must rebuild the signed iOS and macOS artifacts for these exact source hashes, run strict lint and focused native checks through the proven normal Xcode route, then rerun the exact critical iPad case. Only green permits the remaining three iPad history cases and existing task-link navigation controls, followed by phone history coverage. Full phone UI and macOS rendered acceptance remain open, as do tasks 17–20. No new live CloudKit gate, system permission change, wrapper restoration, installation or production activation is part of this repair.


## Verified iOS row repair checkpoint — 2026-10-07

Source `7f9a134e252228e3ff130a82e26c4fe2aaef24f5` (reviewed structural repair `1258f5e` plus formatting only) passes fresh signed iOS and macOS test builds and strict lint across 719 files with zero violations. The initial two formatting lint failures remain preserved separately. The unchanged selected macOS NativeState/EndToEnd cases pass nine declarations/ten expanded cases, zero failures/skips, including both stale and pending-draft arguments. Observed explicit unit-test, isolation-smoke and exact private host inputs enable the retained startup preconditions; these selected cases do not directly assert a smoke snapshot.

The critical iPad case now passes its unchanged accounting Expanded value, retained explanation, saved status changes, recorded references and exact original navigation assertions. The remaining three history cases and two existing task-link navigation controls pass five/five. The four phone history cases finalize with two passes and two failures, zero skips/expected failures: missing/ambiguous and unavailable/over-limit pass; Applied and Reversed fail at unchanged immediate state-label assertions on lines 20 and 64. Accounting/navigation does not execute on the failed phone case. The reason button exists and its tap occurs before either failure; the underlying phone visibility/materialization cause is not yet proven. Failure-only attachment export returns no matching attachments. All three UI results have exact declaration/device identities and verified owned simulator shutdown/deletion. Every owned build/test process is drained and the exclusive heavy slot is released to the parent.

These results verify the iPad accounting repair at this source and reveal a phone presentation regression. A next correction must retain meaningful state-label assertions and independent iOS controls; no speculative correction or blind rerun is included in this checkpoint. Earlier full suites retain their source attribution. The old macOS UI automation initialization limitation and bounded incomplete full phone UI attempt remain separate acceptance gates; tasks 17–20 remain open. Normal Xcode CLI execution follows the user's explicit approval of the omitted controller wrapper protection difference; no tool policy or Mac security setting was changed. Draft PR 255 remains at public head `66f5bd5`; this repair and evidence are local. Exact roots, source digests, finalized counts and cleanup evidence are in `verification-handoff.json` and `/tmp/t2381-ios-row-repair-verification/final-checkpoint.json`.


## Phone viewport traversal correction — 2026-10-07

Saved failure activities expose evidence omitted by the failure-only attachment filter. Both phone hierarchies show the actual reason control `Expanded` at the bottom of the viewport (Reversed y851.7; Applied y868, screen height 874) and no materialized state row below it. The detail Form is a scrolling CollectionView. This rules out a failure to toggle the reason in these snapshots and supports a viewport traversal defect in the test: the immediate Applied/Reversed assertions never reveal the newly separate lazy rows. It does not establish a private SwiftUI rendering mechanism or a new production defect.

The UI test now calls its existing bounded reveal helper for the exact Applied/Reversed text and the exact already_reversed availability text before retaining the same assertions. Product files, labels, waits, payload accounting, recorded/raw status fields, UUID navigation and absence of mutation controls are unchanged. Both internal source reviewers accept this traversal correction without assertion weakening. This source-only correction has whitespace/source review but no build, lint or native execution while Halo owns the heavy slot. The finalized 7f9 phone failures remain preserved.

The ready next-slot plan is `/tmp/t2381-phone-viewport-verification/plan.json`: strict lint plus a fresh signed iOS test build tied to the new test digest, then exact two phone Applied/Reversed cases (boot/enumeration 120 seconds each; execution 420 seconds). Only finalized 2/2 PASS with zero failures/skips/expected failures and verified owned drain/deletion permits the remaining two phone history cases. The remaining gate checks actual targeted source digests, exact native identities, per-device counts, execution exit and cleanup rather than trusting a summary flag. Launch defaults print the plan and start no subprocess. The existing normal CLI route, development signatures/entitlement exclusions and synthetic UI fixtures remain; no controller wrapper or system changes return. Affected iPad traversal checks, bounded full phone UI, macOS automation initialization investigation and final repository acceptance remain in separately allocated follow-up stages. Tasks 17–20 and PR 255 remain unchanged.

Diagnostic evidence: `/tmp/t2381-ios-row-repair-verification/phone-attachments/testRenderedReversedHistory-activities-1.txt` and `/tmp/t2381-ios-row-repair-verification/phone-attachments/testSavedReasonAccountingAndOriginalNavigation-activities-1.txt`, with original activity trees and binary UI snapshots alongside. No screenshot was inferred from a binary snapshot or unavailable frame extraction.

## Phone and iPad verification checkpoint — 2026-10-07

At `e8634d75522106a359affdaeb84d4115a43338c2`, the bounded viewport traversal correction passes a fresh signed iOS test build and strict lint (719 files, zero violations). All 27 compiled phone UI declarations pass across six disjoint scoped runs: 30 expanded executions, zero failures, skips or expected failures. This is complete phone declaration coverage across scoped runs, not one full-suite invocation. The two affected Applied/Reversed iPad declarations also pass with their unchanged exact accounting, saved payload/status/canonical-reference and UUID navigation assertions. Product source is unchanged from `7f9a134`; its earlier signed macOS build, nine focused native declarations/ten cases, four iPad history declarations and two navigation controls retain that source attribution. Earlier full unit suites retain their original source attribution.

The launch execution itself exited 0 and passed one declaration with four distinct dark/light and portrait/landscape argument configurations. The adapter initially rejected the raw native identifier lacking `()`. A source-reviewed metadata verifier reconciled the saved tree against the exact compiled identifier, four configuration names, native/device counts, source/build/signature/command binding and cleanup evidence. No native replay occurred. `/tmp/t2381-phone-viewport-verification/phone-scoped-coverage.json` records the exact declaration union and every result root; `launch-result-reconciliation.json` preserves the adapter discrepancy.

One earlier remaining-history attempt failed before feature execution: discovery reported a missing testmanagerd socket and returned an invalid suite-only inventory, which the gate rejected despite enumeration exit 0. Its diagnostics remain preserved. After a no-space failure during preparation, only three completed, owned, regenerable Intermediates.noindex directories were removed after an exact active-build census; products, logs, results and source were retained. One fresh bounded retry passed. Disk pressure is not established as the socket failure's cause. The final artifact check found about 12.3 GiB free with all seven successful UI result bundles, summaries and logs present, along with build/lint logs and the current iOS products. No build is queued during the user's DerivedData cleanup.

macOS rendered acceptance remains blocked before feature execution. Read-only Developer Tools status reports developer mode disabled; bounded historical logs show the automation request and a timeout 60 seconds later, without a specific permission denial. The backend query had no matching records; that absence proves no cause. The old runner already used normal Xcode CLI, so removing the controller wrapper provides no new Mac retry condition. No global security, settings or TCC change or blind unchanged retry occurred. A working, separately authorized Mac automation environment remains necessary.

All owned jobs are drained and all eight owned simulator attempts are deleted; the heavy slot is released. Tasks 17–20 remain open: task 17 still requires macOS rendered layout acceptance; task 18 depends on 17; composed task 19 has passing source-qualified evidence but depends on 18; final task 20 depends on those gates. Live CloudKit, production promotion and client activation remain outside the approved acceptance scope. Draft PR 255 remains at public head `66f5bd5`; these source/evidence updates are local and unpushed. Exact current source hashes, results, historical attribution, resource recovery and remaining gates are in `verification-handoff.json` and `/tmp/t2381-phone-viewport-verification/final-checkpoint.json`.

## Remaining acceptance after source review — 2026-10-07

Read-only pre-push review covered the seven local commits from `66f5bd5` through `91ff72ad` and all nine changed files. Code reuse, quality and efficiency reviewers found no blocking production issue. Spec review identified two remaining obligations beyond Mac rendering: the composed task 19 test compares normalized parsed retained-page/replay content rather than exact original UTF-8 bytes, and task 20 still requires current-source full iOS unit verification under the repository's before-push instructions. Older full suites and the current focused nine declarations/ten cases remain source-qualified evidence; they do not waive that final current iOS unit check.

The smallest composed correction is prepared and source-reviewed in `/tmp/t2381-macos-automation-nextstep/composed-byte-proof.patch`, with source bindings beside it. It adds raw content-text helpers to the composed fixture and exact UTF-8 comparisons for retained pages after apply/undo, historic receipt JSON and terminal replay. Existing parsed assertions remain. The patch is unapplied, uncompiled and unexecuted. After application, verify the two affected Mac-only fixture-consuming suites: six expected declarations/seven cases, confirmed from actual native identities and both stale/pending-draft arguments. Existing lower-level receipt and frozen-page byte assertions retain their proof; the prepared change closes the explicit composed-workflow obligation.

The actual failed Mac command already used direct normal `Popen(command)`; the controller wrapper fix is present. Saved enumeration exited 0 but contained automation errors and a suite-only placeholder. The old adapter checked those errors after running the full target. A separate prepared guard patch rejects errors and mismatched exact identities before any dependent run. It does not fix the underlying automation timeout. The source-reviewed `/tmp/t2381-macos-automation-nextstep/probe-plan.json` instead proposes one direct Applied/accounting/original-navigation declaration, bounded at 120 seconds, without optional pre-enumeration. Require a separately authorized concrete change in GUI automation context, an allocated heavy slot and matching current signed artifacts; preserve the generated UI target/dependencies/dylibs, use matching plist/CLI method selectors, require exact finalized 1/1 results and executable-verified owned cleanup. The actual probe adapter still needs review before launch. No specific Developer Mode/TCC change is established as the fix, and no unchanged retry is queued.

Task 17 lacks Mac rendered history/navigation proof; task 18 awaits that paired acceptance. Task 19 additionally lacks its composed byte assertion and focused runtime proof; task 20 additionally lacks the current full iOS unit run and final dependency acceptance. Current phone 27/30 coverage and affected iPad passes remain satisfied if their source hashes stay unchanged. Do not repeat those, the already passing native state checks, the other product-identical iPad/nav checks or the closed-store migration solely for these gaps. No live CloudKit/all-writer gate is added. No source patch, build, test, lint, security setting, service repair, push or live write was performed during this preparation. The heavy slot remains released. Exact analysis is `/tmp/t2381-macos-automation-nextstep/diagnosis.md`; review roles, findings and source attribution are in `source-review.json`.

## Composed byte assertions applied; acceptance batch prepared — 2026-10-07

The reviewed two-file task 19 correction is now applied: composed reads/writes expose original content text through fixture helpers; retained pages after apply/undo, historic receipt JSON and lost-response terminal replay are compared as exact UTF-8 bytes. The existing parsed logical assertions remain. These are Mac-only test changes; product and phone/iPad UI test hashes are unchanged. Task 19's source-only byte assertion gap is closed, but compilation, lint and focused runtime proof remain pending. No passing runtime claim is inferred from source review or patch application.

The next coherent batch is `/tmp/t2381-current-acceptance-batch/plan.json`: strict lint and fresh signed iOS/macOS test builds bound to the frozen source, then the affected composed/capability Mac tests (six expected declarations/seven cases, exact finalized identities and stale/pending-draft arguments), then the full current iOS unit target with no selectors/skips and exact compiled/finalized inventory and expanded device counts. Prepared build/unit adapters default to an inert plan; no build, lint, test or simulator launch has occurred. Parent still holds new builds while cleanup/free-space verification completes. Recheck disk, package caches and required artifacts before execution; no cache survival is assumed.

The reviewed one-case Mac UI probe is the final conditional stage. It requires a concrete separately authorized change in the GUI automation environment and matching signed current artifacts; no unchanged retry or specific security/TCC toggle is prescribed. It preserves real UI startup/dependencies and counts exact 1/1 PASS toward the required four Mac declarations, allowing only the remaining three afterward. The actual UI launch adapter must be reviewed before execution. Missing Mac environment readiness blocks that stage, not earlier unit verification after slot allocation. All owned heavy jobs remain drained and the slot released. Existing phone 27/30 and iPad/state/migration proofs remain source-qualified and need no repeat while their relevant hashes stay unchanged. Tasks 17–20 remain open; no push or live write is authorized by this preparation.

## Current acceptance results and Mac authentication blocker — 2026-10-07

At source `74b299cd364204881dd4e4792a4515765220f8ec`, fresh signed iOS and macOS test builds pass, and strict lint passes 719 files with zero violations. The strengthened composed/app-capability checks pass six declarations/seven expanded cases with zero failures/skips, including raw UTF-8 retained pages after apply/undo, historical receipt JSON, terminal replay and both stale/pending-draft arguments. Actual unit/smoke/private-host startup inputs and owned host drain are verified. The current full iOS unit inventory is exactly 1,352 enabled declarations with no disabled declarations; all 1,352 declarations/1,456 expanded executions pass with zero failures/skips/expected failures. Native identities, device counts, execution exit and fresh owned simulator shutdown/drain/deletion are finalized. This closes the composed byte-proof and current full-iOS-unit gaps; older full suites retain their source attribution.

The bounded Mac probe uses the fresh signed development app/runner, unchanged generated UI dependencies/dylibs, matched method selectors and normal Xcode controller. It exits 65 after automation initialization times out, with zero feature declarations/cases executed; the runner-level error is not counted as feature coverage. The remaining three Mac history cases are not started. Runner PID 24007 and controller are drained, with no stalled hosts. The read-only 90-second system-log window now shows a concrete prerequisite: the automation-mode writer requires authentication and invokes LocalAuthentication with reason `Enable UI Automation`, followed about 60 seconds later by the runner timeout. No authentication completion is observed in this bounded window. This is stronger evidence than the earlier developer-mode candidate; no particular DeveloperMode/TCC toggle or definitive sole cause is asserted. No security/settings/service changes or unchanged native retry occurred.

Task 17 still lacks Mac rendered history/navigation acceptance; task 18 awaits it. Task 19's source/focused byte-proof gap is now verified but completion retains its task 18 dependency. Task 20's current full iOS unit gate is now verified but final completion retains the Mac/dependency gates. The next step is native macOS `Enable UI Automation` authentication under authorized environment setup, followed by changed-condition/artifact checks and only the Mac one-case probe, then remaining three on exact PASS. No builds, focused units, phone 27/30, affected iPad or migration rerun is needed while their relevant hashes/artifacts remain unchanged. No live CloudKit/all-writer/production-activation gate is introduced.

The final independent process/simulator census finds no owned job and confirms the one new owned iPhone simulator absent; all prior owned devices remain drained. The heavy slot is released, with about 216 GiB free. Exact source hashes, signed builds, native counts/roots, prior phone/iPad attribution, Mac authentication evidence and final drain are in `/tmp/t2381-current-acceptance-batch/final-checkpoint.json`; the bounded log is `macos-probe-bounded2.log` alongside it. Source and evidence remain local, unpushed; draft PR 255 remains at public head `66f5bd5`. Tasks 17–20 remain open. No additional native job is queued.

## Final Mac rendered acceptance — 2026-10-07

The Mac consumer corrections adapt XCTest to native mouse clicks, DisclosureTriangle roles, numeric expansion values and StaticText values. Queries bind the saved task UUID's exact detail window, avoiding unrelated restored windows. The leading disclosure affordance is clicked using its saved accessibility frame; substantive assertions retain exact reason, Applied state, accounting expansion and explanation, raw changed fields, canonical reference, original UUID navigation and absence of editing controls. No product, fixture, persistence or coordinator code changed in this batch.

At `eb94b1c`, the Applied/accounting/navigation probe finalizes one declaration/one case PASS. The remaining invocation finalizes two PASS (Reversed; missing/ambiguous original references) and one FAIL (unavailable/over-limit label query). The failed case is corrected to query and assert complete native AX values, including the unavailable retry sentence. At `c8d71319`, recovery finalizes one declaration/one case PASS, covering both unavailable and over-limit fixtures, with zero failures/skips. Exact committed source comparison proves that only this failed method changed; all other methods/helpers and product/core sources remain byte-identical. Four passing native declarations/cases are therefore qualified across disjoint runs, without relabeling the mixed-result invocation as a full PASS.

Fresh signed Mac test products and strict lint (719 files, zero violations) PASS at the recovery source. Build/controller/app/runner jobs are drained. Core proof at `74b299c` remains: signed both-platform builds, composed six declarations/seven cases including exact UTF-8 page/receipt/replay bytes, full iOS 1,352 declarations/1,456 cases with zero failures/skips. Phone 27/30 across six disjoint runs at `e8634d7` and affected iPad proofs retain their sources; later Mac-only consumer changes preserve iOS behavior. No unrelated satisfied gate was repeated. Tasks 17, 18, 19, 20 close in dependency order.

Exact final evidence: `/private/tmp/t2381-mac-window-verification-retry12/final-checkpoint.json`. Applied probe: `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/t2381-macos-ui-probe.tc68b3kh`. Mixed result: `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/t2381-macos-ui-remaining.1wo6_s7f`. Failed exact-substring recovery: `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/t2381-macos-ui-recovery.iyewvxml`. Successful recovery: `/var/folders/11/v0tnfm294kd9c6zll_ncmpkh0000gn/T/t2381-macos-ui-recovery.wqvj9iyc`. Prior authentication/init timeouts and selector/input failures remain preserved; automation authentication is no longer an open demonstrated blocker. No distributed atomicity, all-writer fence, live CloudKit schema proof, deployment, live ticket write or main merge is claimed. Feature push and draft PR255 update are authorized after the final pre-push packet.
