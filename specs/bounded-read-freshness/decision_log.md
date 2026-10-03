# T-63 decision log

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
