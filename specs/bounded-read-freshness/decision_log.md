# T-63 decision log

## Squash-main reconciliation and publication approval — 2026-10-04

Parent forwarded explicit user approval for all Transit pushes and sharing changes with the configured Claude reviewer (Sentinel_26fb7496284881918233b3670bb003c1), alongside overnight merge authorization. The previous disclosure gate is cleared. No deployment, client activation or live-data repair is authorized.

T2383 PR250 merged at `e6bde03631b2d4198e9ceff13b49ec56b62b64c3`. The old T63 head `ff6286a` is preserved at `T-63/pre-squash-ff6286a` and in existing native/Pulsar evidence. The dedicated branch is reconstructed on that squash commit with only its unique tests/docs; no already-merged foundation/common production commit is replayed. Newer T2383 breaking-change release notes are retained. All 537 compiled inputs remain byte-identical to verified `dbf3355`, so the exact native/iOS evidence and code reviews remain applicable; fresh lint and review check the reconciled scope. Native stall and overlap qualifications remain binding.

## Final local verification checkpoint — 2026-10-04

All 16 implementation tasks are complete at source `dbf3355d66ab51767fc97ef840dac2ead9c3573b`. Twenty-three finalized native selections cover 2,189 configured declarations exactly once, with 2,425 passing executions and no failures/skips/warnings/issues. Root independently queried actual bundles and verified source/artifact hashes. [Task16 acceptance](task16-green-acceptance.md) preserves five excluded stalled attempts, the Chunk05 post-body overlap qualification, and the adjacent fixture-only priority-inversion repair. The stall cause remains unproved. All heavy jobs are drained.

Parent conveyed overnight push/PR/merge authorization after checks (Sentinel_da18efb69dec819181f52a872520d2fb); deployment, live-data repair, client activation and CloudKit operations remain excluded. That authorization is distinct from external Claude disclosure approval, which is still pending parent forwarding. Creating a PR triggers the repository's automated Claude review and remains held. User-requested pre-push Pulsar publication is part of the authorized local review workflow. Actual installed-client compatibility is separately owner-approved deferred post-merge for T2383.

## Current integration decision — 2026-10-04

The parent confirmed that the already-approved latest-only T2383 contract takes one JSON-RPC object per POST and rejects wire arrays. The original wire-batch and mixed-delivery decisions recorded below are historical foundation context; generic coordinator aggregation evidence remains useful, but final production exposes no dual-era array path. This supersession updates execution guidance without reopening product approval. Identifier batches within `query_tasks` and `mutate_tasks` application batches are distinct.

Implemented portfolio source is consumed at `c123210`: exactly the six owned files from `8478b17`, matching the local owner hash/dependency handoff. The owner independently verified 54 declarations/61 expanded cases at `a3c2a705`; local integrated verification has not run. Stage B uses the confirmed direct `MCPPreparedReadCapture?` entrypoint and retained replay without recapture. Stage C still requires a stable verified integration checkpoint and explicit common-file transfer to T2383, including the extracted `MCPServer+Routing.swift`.

The user approved local builds and tests on the isolated development/test target (Sentinel_10e284fb472881918fb01fad1bde10d2). Heavy jobs still require coordinated exclusive grants. Routine reports remain local; phone/document delivery is limited to spec review or an explicit user request. No live-data write, client activation, merge or deployment is authorized by that testing approval.

## Quick decisions

| Date | Decision | Rationale / authority |
| --- | --- | --- |
| 2026-10-03 | Work on dedicated `T-63/bounded-read-freshness` branch/worktree from `0db453b` | Delegation explicitly requested isolation and allows branch commits; scoped Git administration escalation succeeded. |
| 2026-10-03 | Preserve all other work, including T2380 | Explicit delegation; inspected separate branch/worktree without editing it. |
| 2026-10-03 | Keep feature name, wire shape, budgets, default policy, refresh tool scope, and cross-ticket snapshot ownership pending | These affect caller behavior and shared T2382 contracts; no approval of unseen proposals was supplied. |
| 2026-10-03 | Do not implement or change ticket status before first approval | Actual creating-spec phase gate; requirements skill also requires a name answer. |

## Approval record

| Date | Decision | Rationale / authority |
| --- | --- | --- |
| 2026-10-03 | Full scope, full spec type, and `bounded-read-freshness` name approved | Parent conveyed direct user statement: “Both tickets scope, spec type, and name are approved” (Sentinel_3ccdbb1152c88191b673f3dde9f76e60). |
| 2026-10-03 | Ticket moved to `spec` | Actual creating-spec transition after scope approval; committed Transit revision `r1:aaaffbb389d4c805f835e3b64bb78731f83e85030897c8e7956c8154b42f31ea`. |

| 2026-10-03 | Preserve existing data payloads with additive freshness metadata; default refresh_if_needed; 5,000 ms total / at most 2,000 ms refresh limits; defer separate refresh tool and maintenance reads | Parent conveyed direct user reply “That's fine” (Sentinel_6b71cb52cf10819190043fb6ad347713 replying to Sentinel_c62cd3e9da0c8191aedc90e0eb304f6e). This reply did not approve the 30-second recency threshold or complete requirements. |

| 2026-10-03 | Summary and detailed task queries may use the same saved snapshot; T2382 owns its external API/lifecycle, T-63 shared capture/freshness supports retained identity | Parent conveyed direct user “Sounds good” (Sentinel_5479ed38c0cc8191a7c47a6487b6c0a1) to same-snapshot reconciliation proposal, and assigned ownership. The same reply approved T2382 legacy count preservation/separate counts; those count requirements belong to T2382. |

| 2026-10-03 | Individual reads/read-only batches have a five-second response limit; mixed read/write batches produce the read result within five seconds but delivery may wait on writes | Parent conveyed direct user “That's acceptable” (Sentinel_a44f8dbe8f1c8191a055e45169b5e685) replying to that exact distinction. Preserves write behavior without claiming an overall mixed-batch delivery deadline. |

## Requirements choices (now approved)

The requirements draft recommended a 30,000 ms recency threshold, eight unfinished reads as an operation-count admission bound, and server phase/late-completion diagnostics. Those requirements decisions are now approved as recorded below. Exact design mechanisms and tasks retain their separate approval gates.

## Requirements approval

| Date | Decision | Rationale / authority |
| --- | --- | --- |
| 2026-10-03 | Both final requirements packets and all decisions within them approved, including 30-second threshold, eight physical unfinished reads, and latency diagnostics | Parent conveyed direct user “Both are approved for all decisions, including the ones in the requirements review” (Sentinel_fa39017e21a08191abdcd0b7ae6c9e8e). Design, tasks, and production implementation are not approved. |
| 2026-10-03 | T-63 is single writer for shared MCPServer, MCPToolHandler init/dispatch/read-only registration, MCPToolDefinitions wiring, and shared metadata DTOs | Parent coordination; T2382 supplies separate summary/snapshot query/schema modules and owns reusable snapshot lifecycle/API. Coordination is not user design approval. |
| 2026-10-03 | Return saved data only for MCP reads/summaries | Parent conveyed direct user “If something isn't saved, it shouldn't be returned” (Sentinel_bb00a4d9d8688191a33a0e6a34ea38db). Requirement 2.6 and fresh-context design follow this explicit clarification; no need to ask again about pending UI edits. |

## Design ADR 1 — independent physical work and response completion

Use transport-side one-shot completion with an independent strict deadline timer. Keep each underlying worker admitted until it physically finishes, including after timeout and server generation changes. A structured task-group race waits for non-cooperative children at scope exit; a MainActor timer cannot run during a blocked fetch. Neither satisfies the approved response deadline.

The standalone Swift6.4 prototype measured the default asyncAfter timer returning at 5,164 ms despite a 4,850 ms schedule. A strict DispatchSourceTimer with zero leeway, userInitiated queue, and explicit @concurrent entry produced eight encoded timeouts by 4,850.49 ms and their batch by 4,851.15 ms while MainActor was blocked for six seconds. Eight unfinished slots persisted until work actually completed; restart did not reset them; no late publication occurred. This validates the isolated mechanism, not complete production transport performance.

## Design ADR 2 — fresh capture plus persistent history fence

Capture saved state from a fresh autosave-disabled ModelContext in one nonawaiting MainActor turn. Read the latest public persistent-history token/storeIdentifier before capture and again through a fresh validation context afterwards; reject unequal/unavailable/invalid fencing. Copy only immutable DTOs and bytes across executors. Do not transact, save, or roll back the UI's shared context.

The isolated SwiftData probe injected a saved project/task change between selected fetches. It observed old/new values but detected a changed history token and rejected that view; a stable fresh context returned saved new/new values. MainActor serialization alone excludes local actor reentrancy but not CloudKit/background store commits. History fencing supplies a measurable consistency check without private Core Data context access. CloudKit import/history identifier and visible-history completeness still need live signed-app verification; freshness remains unknown if association cannot be proved.

## Merged foundation verification

PR249 is merged at `201205bd4e786c7f152d8f99006b37da7da888c7`, also current remote main. Its tree is identical to previously inspected T2380 head `b618acf9e3d66a4a1ce493eea94091c058721731`; canonical r1/comment behavior needs no design change. Align the dedicated branch before production implementation, preserving this spec work and all other worktrees.

## Design ADR 3 — shared publication transaction

T-63 and T2382 agreed one common publication lock domain with pre-encoded success/rejection bytes, pending-plus-published capacity, same-store batch coalescing into one immutable index candidate, atomic child-reservation transfer, validate-all-before-any-commit, and one index swap per store. Read-only batch selection publishes all selected children together or discards all. Stale append CAS returns READ_BUSY rather than overwriting another index. Internal peer review identified the same-store lost-update gap and the design adopted this correction. These mechanisms remain proposed until final design approval.

## Shared scope clarification before design gate

`CapturedReadView.captureScope` is typed as whole portfolio, selected resolved physical project keys, or ordinary selected query. `completePortfolio` means complete declared reusable scope plus identity/comment closure, not necessarily every global record. Closure records do not enlarge selected counts; reusable queries outside declared scope fail. T2382 requested this explicit DTO contract and T-63 confirmed it before design approval.

## Design approval

The user approved both designs unchanged: “Both 63 and 2382 are approved without required changes” (Sentinel_541ceb19e7c8819193d04d23c5263041), conveyed by the parent. Approval covers T-63 `5639c40` and T2382 `3932e88`, including final typed scope and publication amendments. Task planning is authorized; the task list and production implementation still require the next explicit approval.

## Tasks approval and implementation start

The user approved both task lists: “Tasks approved, but why so many explicit mentions of xcode27 in there?” (Sentinel_c2e9343628948191b921868234aaf409), conveyed by parent. Implementation is authorized with the approved DAG/red-green evidence. The toolchain constraint remains recorded once in repository guidance; routine reports should avoid repeating it. The dedicated branch was rebased cleanly to merged `201205bd4e786c7f152d8f99006b37da7da888c7`, preserving five spec commits and all other worktrees. T-63 has the initial exclusive heavy build/test slot for foundation tasks 3/7/9 and must tell parent when released. No merge/deployment is authorized.

## Verified interface-only foundation

Commits `1b34efb` and `52e4882` define actual shared interfaces; focused typechecking and lint passed. T2382 confirmed the DTO fields satisfy its handoff. Requested comment-body JSON is optional with includeComments=false; complete portfolio canonical revision/full no-comment record/comment identity evidence remain mandatory. Stable MCPPublicationStoreID and MCPReadPublicationParticipant.prepareAggregate provide same-store grouping before terminal selection; task 9 owns concrete single-domain registry/lookup/reservation/retirement behavior. This is an interface handoff, not runtime risk verification.

## Foundation implementation review checkpoints

The import/refresh stream passed ten focused app tests at local `8d69d65`. Independent internal design review subsequently found that a non-applicable same-store completion could replace an applicable completion before polling or capture. Requirement 3.6 requires retaining that outcome. The repair adds bounded active observation windows and A/B ordering regressions; production nil-proof unknown/null behavior remains unchanged. The earlier passing suite is not treated as final verification of the repaired stream.

The capture/coordinator stream passed twelve focused app tests before the remaining large-input and initialization-race cases: seven actual SwiftData capture cases and five transport/permit/batch/terminal-race cases. Live signed-store import applicability is not established. Stable local persistent history is a capture boundary, not proof that a specific remote import is visible.

Read-only review identified a batch initialization race: stop could select an individual timeout before the complete array fallback was installed. The approved whole-array contract requires atomic same-generation admission with terminal selection deferred until the prebuilt full fallback is ready. The worker is adding forced stop/cutoff interleavings. Bulk fallback preparation remains outside the common publication lock; the original admission timestamp does not reset.

Parent's separately approved latest-protocol T2383 migration does not alter the currently approved T-63 foundation work. Keep the coordinator transport-neutral and the current batch adapter separable; do not add dual-era behavior or remove approved batch tests before coordinated integration.

## Fixture foundation verified

Tasks 2/3/6/7 passed 17 focused actual app tests, including saved-only SwiftData/canonical revision and real Hummingbird encoded availability. Large fallback admission/stop/cutoff races were corrected before handoff. Exact measured values, preserved result paths, observation-hook limitations and the coordinated task 9 registry contract are recorded in foundation-handoff.md. No signed-store import-visible proof is claimed; approved unknown/null/unavailable and incoherent_capture fallbacks remain binding. Tasks 8/9 are handed to a fresh parent-coordinated implementation delegate; no competing heavy job remains.

Both completed streams were integrated locally on the dedicated branch at `7f5d7ce`. The repaired import stream passed fourteen actual app tests at `e11979c`; independent review confirmed the A/B evidence correction and found no new lifecycle/bounding issue. Register its observation window before the decision snapshot and hold it until capture metadata is frozen. Evidence is preserved outside Git under `t63-review-evidence/foundation/` and `t63-review-evidence/import/`; only the two completed stream worktrees were removed. Tasks 1–7 are complete; publication task 9 still gates the verified T2382 runtime handoff. These local integrations are part of the authorized implementation workflow; upstream merge/deployment remains unauthorized.
