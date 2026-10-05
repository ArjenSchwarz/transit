# Safe task consolidation — decision log

## Approval state

| Gate | Evidence / state |
| --- | --- |
| Resume planning | Owner `Sentinel_c4dd914497c08191bc5612ccddd5449c`: “While Asterism is ongoing, start on the spec for 2381 and start planning the work for Meddy”. This branch owns T-2381 only. |
| Scope, route and name | Approved by owner Sentinel_330b41f7115481918e53c2e1480c5dbc, replying “Approved” to Sentinel_efafa185b128819198b0fb0f045ba886; exact reviewed checkpoint 2bc58bbd. This approval permits requirements only. |
| Requirements / design / tasks | Requirements approved by Sentinel_1e5655b5fba48191b5a5be8602d0cf1b against b1d02591dd214f1d2ca6cf3f196b52b01058076a and Library packet libfile_25ec8d9d5da48191875d258b9c419406. Design draft under review; tasks not started. |
| Implementation | Not authorised by this planning instruction. |
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

Status: design proposal pending approval.

Context: approved whole undo and permanent inspectable history need durable attributable before/after evidence beyond seven-day receipts, while CloudKit can import physical collisions and partially available history.

Decision: one additive TaskConsolidationEvent entity records immutable apply/reversal events with scalar participant lookup and versioned bounded payload. Guard original operation history separately with o1; task r1 remains the merged field/comment/link token. Both event and actual group effects/terminal receipt share the existing owned save.

Alternatives: an expiring receipt alone loses long-lived undo/history; mutable task-local reversed flags can overwrite provenance and require rewriting generic task tokens; separate persistence cannot use the existing same-store save boundary. Costs: additive migration and explicit history decode/ambiguity/byte checks. No new distributed coordination guarantee follows.

### ADR 2 — Existing retained publication for exact reviewed proposals

Status: design proposal pending approval.

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
