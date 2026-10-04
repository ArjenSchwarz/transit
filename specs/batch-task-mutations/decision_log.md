# Decisions: Batch Task Mutations

## Quick Decisions

| ID | Date | Decision | Rationale / evidence | Status |
| --- | --- | --- | --- | --- |
| Q1 | 2026-10-03 | Use full Starwave specs; feature name `batch-task-mutations`. | User: “2384 fully approved” in parent, `Sentinel_4fd40b3fecf48191a57ce03897d3e7ec`, approving the scope/name gate. | Approved scope. |
| Q2 | 2026-10-03 | Create isolated branch/worktree before later gates. | Explicit initial delegation; base `201205bd4e786c7f152d8f99006b37da7da888c7` verified against main/origin/main. | Authorised setup; no implementation approval. |
| Q3 | 2026-10-03 | Use design critic then internal peers for formal reviews. | External disclosure remains unauthorised; local peer-review-validator documents internal subagent fallback. PERSONAL_PROJECTS=1 does not override user disclosure restrictions. | Required review mode. |
| Q4 | 2026-10-03 | T63 owns existing MCPServer/MCPTypes/common dispatch/schema wiring until handoff. | Delegation and approved T63/T2382 read-only designs. | Coordination constraint. |
| Q5 | 2026-10-03 | T2383 adapter preserves historical T2380 terminal JSON and outcome meaning. | T2383 coordination message: preserve text, unknown/missing fields, accepted/outcome/retryAction; no live reread or terminal receipt rewrite. Latest-only T2383 scope and requirements are approved; its serializer design remains unapproved. | Shared constraint; concrete envelope still proposed. |

## ADR 1: Per-item commits and stop-on-first-unsuccessful execution

Status: approved requirements decision at `Sentinel_35dae4e67398819184369b41649ec75b`.

Context: canonical task updates must precede duplicate closure. Existing T2380 guarantees attach to a protected tool/item key with acceptance and terminal result persisted in the originating store. Whole-batch atomicity would require a different persistence/recovery boundary and cannot promise global CloudKit ordering.

Decision: propose ordered independent item commits and stop after the first rejected/in_progress/uncertain item; return unstarted items explicitly. Batch retries use item keys and can continue past earlier committed replays. A retained rejection must be excluded or corrected with a fresh key after review before later items can proceed; transient rejection may instead direct same-request retry. Only understood authoritative commitment permits progression. Unknown/unreadable outcomes stop the batch without assigning a fabricated receipt state.

Alternatives: whole-batch local transaction (different receipt design, larger recovery scope); continue after rejection (allows closure after failed canonical update); compensating rollback (creates new effects and conflicts).

Consequences: earlier effects survive later failure; one submission is not globally atomic. A lost aggregate response needs item reconciliation. The user must approve the exact behavior in requirements before design.

## ADR 2: Stable item targets and no within-batch revision chaining

Status: approved requirements decision at `Sentinel_35dae4e67398819184369b41649ec75b`.

Context: repeated updates to a task change its revision, and display-ID/UUID aliases complicate duplicate detection and replay identity. The motivating status-plus-reason effect already exists as an atomic T2380 item.

Decision: propose task UUID selectors only, one operation per normalized target UUID per batch, and caller-supplied operation key/revision. Multiple changes to the same task use existing combined status/comment or a later call.

Alternatives: allow repeated targets with literal revisions (later revisions generally stale); predicted revision chaining (new contract and coupling); combined update/status/comment item (new atomic operation beyond existing protected tools).

Consequences: simple stable payload identity and shape checks before execution, at the cost of another call for separate same-task property/comment edits. Limit 50 is proposed as a bounded initial API choice, not a performance claim.

## ADR 3: Advisory preview without receipt inspection

Status: approved requirements decision at `Sentinel_35dae4e67398819184369b41649ec75b`.

Context: dry run must not mutate guard/receipt state or trigger recovery. T2380 matching-key replay can legitimately return a historic commit when the current target has changed or disappeared.

Decision: propose validation of current local domain state only, all-item diagnostics, proposed normalized changed fields, and explicit unchecked key state. Do not simulate saved timestamps/UUIDs/revisions or promise durable availability. Execute replays first under the authoritative write contract, or validates a new write independently.

Alternatives: reserve keys/revisions during preview (violates no-write preview); inspect/recover receipts (adds recovery side effects and unavailable-store complexity); label preview as future commitment guarantee (false under concurrent local changes/sync).

Consequences: a stale or missing current target can yield an invalid preview while a retained submission replay remains committed. Current state success does not certify key availability or future write durability.

## Requirements review resolutions

| Finding | Resolution | Basis |
| --- | --- | --- |
| Critic: unknown/unreadable item result could continue execution | Stop unless authoritative commitment is understood; preserve available original text/flag and correlate not_attempted items. | Prevent further effects after an unverified result; classification remains receipt-owned. |
| Critic: historical nested isError omitted | Preserve item result flag separately from aggregate error flag. | T2380 resultJSON/resultIsError are authoritative. |
| Critic: transient responses described as durable outcomes | Advance only on confirmed commitment; no terminal-retention claim for transient responses. | Existing accepted:false retry_same_request responses do not imply a terminal receipt. |
| Critic: shape/domain boundary and failed-item correlation ambiguous | Type/safety formats fail whole shape; invalid enum domain values or missing status-comment author fail individual items; diagnostics include index. | Matches existing protected write stage distinctions. |
| Critic: UUID normalization could alter request binding | Normalize only collision detection/mapping, preserve original arguments. | T2380 canonical JSON binds the original UUID string; case changes are not silently rewritten. |
| Self-review: caller timeout versus server interruption | Define interruption by observed cancellation/execution failure. | Lost delivery alone cannot prove whether server continued. |

| Peer API: preserve unknown historic JSON and raw text bytes | Require complete lossless nested outcome/raw-text preservation without fixing serializer schema. | T2383 adapter must not drop historic fields or reconstruct authoritative original text. |
| Peer recovery: missing first-response expiry | Explain submission-time context, unknown protection duration and absent-receipt non-proof; cover response loss then receipt removal in tests. | T2380 allows expired removed keys to execute anew; client must reconcile rather than assume indefinite protection. |
| Peer recovery: old canonical replay before new closures | Explain replay is commit-time evidence, not certification of current canonical contents; caller reconciles stronger workflow conditions. | Preserve replay-first guarantee and avoid adding implicit revalidation or whole-batch atomicity. |

## T2383 latest-only scope coordination

T2383 reported explicit user approval of latest 2026-07-28 only, with no legacy transport, for its scope/name gate. Its requirements are approved; its serializer interface remains under design review. T2384 remains one application-level tools/call and does not require JSON-RPC transport arrays; requirement 6.4 refers to the transport ordering supported by that approved protocol contract. Supplemental classifications and links must stay separate from historical data even if unknown keys collide. Exact envelope/interface remains a design coordination item; T63 still owns the shared transport handoff. T2383 reported installed-client readiness as a blocker; T2384 has changed no client configuration. This coordination does not approve T2384 requirements or T2383's unseen design.

## Design gate context

Requirements at `9b5122c` were explicitly approved by user: “2384 requirements approved”, `Sentinel_35dae4e67398819184369b41649ec75b`. T2383 requirements approval was verified separately at `Sentinel_39b0ca45b1b8819180ac6d9600578f0b`; its design remains under review. Both facts are approvals of requirements, not implementation.

## ADR 4: Reuse receipt execution with a batch-only commit validation policy

Status: proposed design decision.

Context: `TaskService.findByID` selects the first UUID match. A preflight lookup before calling the coordinator could reject a valid historical replay, and a lookup before an await could miss a new ambiguity.

Decision: add an optional internal batch-only validation callback to coordinator execution, evaluated synchronously in the existing fresh commit phase immediately before domain apply. The callback validates one live task for the UUID. Replay and active-key outcomes bypass it. Default nil preserves existing callers; no key arguments, reservation/receipt stores, recovery or schema versions change.

Alternatives: global service lookup change (changes standalone behavior); separate batch receipt engine (duplicates safety); pre-call identity check (breaks replay-before-live-state and leaves a race).

Consequences: small coordinator integration edit with targeted replay/commit tests, without a new transaction boundary or guard subsystem.

## ADR 5: Saved-only non-saving preview context

Status: proposed design decision aligned with explicit owner constraint.

Context: owner said “If something isn't saved, it shouldn't be returned” at Sentinel_bb00a4d9d8688191a33a0e6a34ea38db. Approved AC2.1 does not require pending values; AC2.2 requires pending state remain unchanged. Existing shared service context is container.mainContext and T2380 can save its baseline changes.

Decision: preview owns a fresh ModelContext over the persistent container, autosave disabled and pending changes excluded. Validator services use that context. Unsaved UI values are never copied/output or flushed. Label saved_local_store observation and advisory difference from later saves/imports. Temporary fallback records are not returned as saved evidence.

Alternatives: shared context pending-value preview (contradicts owner); saving pending UI state before preview (violates AC2.2); mutate-and-rollback preview (risks unrelated edits).

Consequences: preview can describe saved data that differs from pending UI forms; execution cannot flush those forms and stops while shared context is dirty. Changes saved independently after preview can invalidate revisions.

## ADR 6: Stop batch writes rather than flush unrelated UI edits

Status: proposed design decision implementing owner no-flush constraint.

Context: TransitApp injects container.mainContext into existing services/coordinator; its fresh acceptance/commit/recovery phases can save baseline pending changes. Checking only the outer loop misses UI edits arising during awaited preparation.

Decision: batch-only execution policy requires a clean shared context at fresh synchronous phase boundaries, before baseline/recovery/rejection saves. Default nil retains standalone behavior. Dirty context first uses the existing store APIs for read-only retained terminal replay/key-reuse detection, with no repair/recovery/task reads. New acceptance or unresolved recovery is blocked; postaccept dirty detection returns uncertainty without flushing/rollback/terminal save. Accepted bindings remain retained, using existing recovery when context is independently clean.

Alternatives: globally replace all MCP services with an isolated context (larger existing-write behavior change); separate batch reservation/receipt engine (duplicates safety); save/rollback dirty context (violates owner instruction).

Consequences: dirty UI state temporarily prevents new batch writes or unresolved recovery through this shared context, while valid saved replay/key conflicts remain available; conservative uncertainty never implies no effects or fresh-key permission. Policy must cover every post-await cancellation/error path, not merely pre-apply identity check. TDD fixtures are required before integration; no guard storage format/files or new recovery implementation is changed.

## Quick Design Decisions

| ID | Decision | Rationale / status |
| --- | --- | --- |
| Q6 | Proposed public tool `mutate_tasks`, mode plus nested explicit operations. | Parent asked for naming preference; concrete design gate owns approval. No outer durable key. |
| Q7 | Batch-local immutable result evidence and logical aggregate adapt once via T2383. | T2383 proposed MCPResultSource + collision-free source/presentation wrapper; exact common API remains its design gate. Avoid inventing common production signatures. |
| Q8 | Pre-encode a compact recovery fallback before executing any item. | Full aggregate encoding can fail after durable effects. Fallback uses input indexes/tool/key/UUID and reconciliation direction, not fabricated receipt classification. |
| Q9 | Generated property tests with seeded cases in Swift Testing. | Existing toolchain; no dependency or build introduced during design. |

## Design critic resolutions

| Finding | Resolution |
| --- | --- |
| Fallback could invoke failed common encoder again | Prepare complete deliverable modern HTTP body bytes via the agreed T2383/T63 adapter before effects; selection is encoding-free. No shared adapter contract means no batch execution. |
| Commitment predicate underspecified | Enumerate strict v1 types/tool/key/identities/revisions/error-flag/terminal-date checks. Current expiry affects replay protection, never established commitment. |
| Cancellation lacks blocker before first/between items | Explicit stop reason/next-unstarted index/optional blocker. Noncommitted returned result retains precedence; all committed wins after-last cancellation while delivery may be suppressed. |

## Owner saved-only amendment and peer clarifications

The initial design's pending-observation preview was replaced after explicit owner evidence arrived, not approved by the prior peer reviews. Amended design requires fresh saved-only preview and clean shared-write phases to avoid flushing unrelated UI edits. No approved requirement mandates unsaved observation, so the requirements gate is not reopened. Repeat critic and both peer reviews cover the amendment before design gate.

Batch domain status/type/priority schemas use descriptive allowed-value lists without enum/const constraints; invalid string values remain item-domain errors. Fallback logical summary is serialization_failed with batch effect evidence unestablished; T2383's phrase outcome_unknown denotes this recovery meaning, not a second T2384 field/outcome namespace.

Amended critic identified AC4.2 conflict in a receipt-blind outer dirty block. Resolved with a non-mutating terminal-inspection branch of the existing coordinator using existing binding/durable-receipt lookup/validation. Valid terminal replay and key mismatch remain available while dirty; unresolved evidence/new acceptance is unavailable. Added an explicit table for every baseline/save/rollback/recovery route and direct-return-before-phase rule so unrelated UI edits cannot enter rollback handlers. No availability exception to approved replay is proposed.

## Final design review synthesis

Critic and two independent internal peers re-reviewed the saved-only/dirty-context amendment and cleared the design gate. They agree AC4.2 terminal replay/key conflicts remain available read-only while dirty; every fresh phase has direct-return guards before save/rollback/recovery handlers. Required early fixtures cover dirty committed/rejected replay, mismatched payload, missing/inconsistent sidecar, expired/unresolved evidence, and both post-await preparation continuations. Complete fallback, exact evidence predicate, schema/domain boundary and cancellation precedence are settled design instructions. No external services or implementation tests were used. Numeric version predicate follows T2380 canonical value equality (1 and 1.0 equivalent), not Boolean/string coercion.

## Design approval and task planning

Owner approved T2384 design `a5950e9` and T2383 design `7970a9c` in parent: “2383 and 2384 are approved” (`Sentinel_717be95229c48191a7c41b6e5e467e4c`). ADR4–6 and Q6–9 are approved design decisions. Proceed to Rune task planning only; task and implementation approvals remain outstanding. T63 owns shared wiring and heavy-test slot. Noncircular seam order is T63 handoff → T2383 common source/encoder/schema/fallback delivery tested with synthetic aggregate → T2384 consumer/registration tests. T2383 common delivery never depends on production batch integration. Single stream avoids conflicting coordinator/integration edits.

## Task plan review resolutions

Actual Rune authored 14 pending tasks, seven adjacent RED/GREEN pairs, one stream and stable-ID blocked_by relationships. All 32 AC anchors are covered; graph has no cycles. Critic first then recovery and integration peers cleared after clarifying new effect allocation versus parsing saved values, post-await versus impossible synchronous UI interleaving, named external API gates and actual MCP/Writes source paths. No scope/design change or source implementation is included. Task approval remains pending; only separate implementation authorisation may start coding, with T63 ownership/slot and T2383 delivery conditions preserved.

T2383 current Rune draft IDs verified read-only: source3/gpzncvn, presentation5/gpzncvp, bytes7/gpzncvr, schema9/gpzncvt, shared delivery15/gpzncvz. Batch consumer gate requires delivered15 commit/interface and these components, not design or task approval alone. T2383 final22/gpzncw6 does not wait on production batch. No dependency direction or scope changes.

## Task and conditional implementation approval

Parent verified owner “Approved” (`Sentinel_edf7fd12288c819192ad45a04154372a`) to “Do the tasks look good, and may it proceed with implementation once its shared dependencies are ready?” for plan d592907. Tasks are approved and implementation is conditionally authorised. Begin independent task1 safety fixtures only; coordinator edits await parent ownership agreement, common consumer tasks await DELIVERED T2383 task15/interface, heavy app tests await parent grant (T2382 owns current slot). Use actual make-it-so single-subagent delegation and approved Rune DAG. No settings/activation/push/merge/deployment approval is inferred; full prepush/Pulsar review remains completion gate.

## Implementation ownership confirmation

Parent confirmed T63 has no active write-coordinator changes and granted T2384 sole ownership of MCP/Writes/MCPWriteCoordinator.swift and coordinator-specific tests for the approved batch-only policy. T63 retains common read/server/types ownership. T2383 task/implementation approval is now granted but delivered task15 is still future; no consumer integration claim follows from approval. Heavy-test slot remains T2382 until parent grants it. Task1 fixture drafting is in progress, and its verified RED remains outstanding.

## Shared source resource cap coordination

T2383 owner approved a 32-container parser-input depth cap at Sentinel_9536d4df532c81919792e70801f128fb (amendment4a9d1be): root object/array counts1, scalar0. Over-cap retained source preserves original raw text/isError with unreadable/unestablished parsed evidence; no receipt rewrite. A readable original receipt can exceed32 after batch wrapper containers are added, so generated aggregate resource failure after effects selects the already prepared shallow complete serialization_failed bytes, never no-effect/fresh-key advice. Giant itemId/raw record/entity link data must not leak into compact fallback through common presentation/context. These are explicit consumer fixtures for existing AC5.2–5.4, not task15 delivery or guessed implementation. Shared delivery remains future.

## Verified API15 consumer preparation

Read-only verification now finds T2383 DELIVERED15 handoff `b21e358c8a5ea1e287afe332c1fc50d83303ce19`, runtime source `543c4a757e4cb7f9f73c973d7cb1be5725c8f342`. All 28 common files and 21 retained-owner files match their runtime manifest hashes. The consumer external delivery prerequisite is satisfied; later common tasks16–22 remain separate obligations. Preserve the reported verification limits: 98 passing bodies from the earlier unfinalized run plus two finalized corrected passes, without claiming a single clean finalized100 run.

Exact ten-file pure source/encoder dependency import is committed in `fe1c57f`. `api15-consumer-import.json` records hashes and confirms the coordinator, App, project and Makefile were preserved byte-for-byte. This import does not deliver modern server registration, retained-read integration or the approved isolated host setup. Task3 RED fixture drafting consumes the actual source/encoder declarations; no GREEN implementation or runtime verification is implied.

The ticket worktree still differs from the delivered isolated development target in App bootstrap, project/schemes, persistence helpers and signed-host preflight. Do not execute the old test-quick host. Before app-host RED execution, obtain the exact owner-coordinated isolation patch, apply it without importing unrelated read/server wiring, verify target and signed-host safeguards, then request the exclusive focused test slot through the parent. Live writes, activation and production launch remain held.


## Final implementation acceptance

All 14 approved tasks are complete at worker evidence commit `0298daa4`; tested source is `5c42c7e`. Parent-approved shared handoff and the verified T63/T2383/T2382 baseline were integrated without competing ownership. Four internal reviewers and the root cleared the actual modern batch route, complete fallback and historic evidence boundary. Fresh finalized full macOS 2409/3049, isolated iOS unit 1289/1334 and UI 21/24 acceptance passed with no failures, skips or native runtime warnings; full lint passed. Actual proof and 31 independently verified artifact hashes are in `task14-green-actual.json`. No external review service, production write, client activation, push or merge occurred. Later T1734 scope remains separate; client readiness and specific publication/disclosure approvals remain release boundaries.

Local pre-push HTML was generated by the installed renderer and archived by Pulsar with exit0 at the path recorded in `local-review.json`. Source inspection established local file-only archive behavior; no external peer-review/forge request or global configuration change was made. Root completed the single phase changelog and overview/explanations; final handoff distinguishes local acceptance from publication/client gates.


## Publication checkpoint: automatic push rejection

The reconciled current-main feature passed all fresh native acceptance and internal reviews. Pulsar archived its pre-push report locally with exit0. Automatic approval review rejected the proposed `git push -u origin HEAD` to `git@github.com:ArjenSchwarz/transit.git` before execution, citing private source/documentation egress and no explicit destination/payload approval in recognised trusted messages. Prior owner approval is recorded in handoff context; no alternative tool, route, worker or indirect execution was used to bypass this rejection. Local bookkeeping was committed independently. No PR, external Claude review or merge occurred. Parent must establish recognised authority before the same approved PRPilot workflow resumes.
