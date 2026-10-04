# Focused catalog READ_FAILED RED and fixture-port handoff

Current acceptance: all six catalog fault cases and thirteen original diagnostics/caller bodies finalized GREEN at integrated b8c8194. See [task15-green-acceptance.md](task15-green-acceptance.md). The chronological RED/source handoffs below retain their original limitations.

Tested HEAD: `63d8dac9f7e76f2469b48895b7df1d7a54def1fd`, with approved test/production source `fc2096d6f1d7890fe6380300988740b2a6627cfd`. The HEAD delta consists only of documentation. No production change or GREEN patch was applied during the RED run.

## Actual focused RED

Xcode 27 build-for-testing, isolated development-host preflight and compiled enumeration passed. Enumeration enabled exactly one declaration, `MCPReadCatalogFailureTests.executionFaultKeepsMachineCodeAndFailureEvidence(tool:category:)`, expanding into six bodies: get_projects/query_milestones crossed with storage_failure/serialization_failure/incoherent_capture.

The console independently demonstrates all six bodies started and completed in 0.012 seconds. Each produced exactly the intended missing READ_FAILED machine-code assertion at line 74; there were six issues and no other observed assertion issues. Failure metadata, error flag, identity, policy, no successful snapshot/asOf, no publication and physical completion controls reached without observed issues. These are console observations, not finalized xcresult counts.

Runner finalization then stalled for more than 180 seconds. Exact owned runner and guarded host were sampled before scoped SIGTERM. Actual runtime exit was -15; the runtime xcresult lacks Info.plist and summary extraction exits 64. The cause remains unproved. Raw destination/AppIntents warnings are retained; no finalized runtime-warning, global-issue or skipped-test classification is claimed. Build exit and inventory exit were both zero.

The worker drained both owned runtime processes and released the heavy slot before extraction. An independent scoped process check also found all four recorded build/inventory/runner/host PIDs absent. No retry or GREEN was applied during that run. Parent accepted the meaningful six-body RED evidence with its finalization limitation and approved the narrow GREEN source repair. Runtime GREEN remains queued after the other workers; no heavy run is authorized by that source approval.

Evidence: `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/catalog-read-failed-red-fc2096d/manifest.json`; raw `catalog.log`, samples, cleanup receipts, extraction results and `root-postrun-review.json` are beside it. Root independently rehashed all 46 indexed artifacts and all 91 MCP plus 16 critical source entries against both disk and approved git objects.

## T2382 source-only fixture ports

Recipient pin: `a9ee19537c790b5d6103a54d0c8c70b17bdc6b5c`. Seven T63-owned fixtures are externally staged; no recipient worktree/index, production source or shared helper was changed. Their caller-local modern request metadata/headers, independent twelve/fourteen tool-name oracles, three query schema branches and coordinator async NIO cleanup preserve the original declarations and behavioral controls. One additional throwing-body test checks error preservation and bounded cleanup.

Packet: `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/t2382-owner-fixture-ports/handoff.md`. Combined patch SHA256: `b3823daf6b09835d65124efd6b3756244ed47234c2181736db1fffefc79dbe77`. Root independently verified all 21 indexed artifacts, seven recipient git-object prehashes, seven staged posthashes, and read-only application with whitespace errors rejected. Targeted lint/parse pass; no Swift typecheck or runtime acceptance is claimed. Actual focused selectors require compiled enumeration and parent slot coordination. The existing shared HTTP helper retains its EmbeddedChannel lifecycle; any observed diagnostics require a separately coordinated fix.

Parent assigned historical `Transit/TransitTests/MCPWriteLifecycleTests.swift` to T2383 for transport adaptation only; coordinator logic and test semantics retain T2384 consultation. Its modern notification/array migration, bounded accepted-cancellation rendezvous and unreached missingSafetyIsRejectedWithoutReservingAKey control are not changed by this packet.

Task15/Task16 remain incomplete. Original ten-declaration/thirteen-body diagnostics GREEN is still unexecuted. No full suite, iOS run, live preferences, installed-app activation, push, merge or deployment occurred.

## Approved source repair and integrated diagnostics review

Parent accepted this RED evidence with its finalization limitation. Narrow GREEN source is committed at `d2648f699a7ebb4426180ef3800f3f70fdf7c07d`: exactly MCPReadService.swift and MCPToolDefinitions+ReadGuidance.swift, matching the approved prospective posthashes. Only READ_FAILED of get_projects/query_milestones changes to JSON. Existing query_tasks errors, other text error declarations, metadata, error flag and original fixtures remain unchanged. Strict targeted lint, syntax parse and diff checks pass; runtime GREEN is unexecuted.

Root source review found no implementation blocker: nil provider sidecar follows the existing generatedJSON default, while readOutcome and the provider adapter preserve the metadata-derived semantic category. Root independently rehashed all five evidence artifacts, both source git objects/disk posthashes and four unchanged fixture paths. Read-only application against T2383 recipient 0071ca4 passes. The recipient component SHA256 is `f3c3fc31297e0a2527e803827bd398bb74438831a00cab821bdd5a95a734ed6f`; exact manifest and root review are in `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/catalog-read-failed-green-source/`.

T2383 integrated the earlier diagnostic production component at bd5c42a. Root verified all twelve owned files remain exact fa58dc0 posthashes at observed recipient 0071ca4 and both approved Handler/App constructor hunks are present. Evidence: `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/task15-source-preparation/diagnostics-recipient-integration-root-review.json`. This is source verification, not runtime acceptance or installed-app activation.

Acceptance still requires actual six-case modern JSON/source/category GREEN and the original ten-declaration/thirteen-body diagnostics controls under a parent-granted exclusive slot, with finalized evidence, retained diagnostics and physical drain. No runtime job runs while T2384 task9 is active. Seven fixture ports are relayed through parent for T2382 integration/focused verification; historical transport adaptation belongs to T2383 with coordinator logic/test semantics consulting T2384.

## T2382 recipient-specific source follow-up

T2382 integrated the seven fixture ports at 4b4ecf3571972aef139154a5c50b5504931970d3. Its service lacks the surrounding diagnostic refactor and guidance file, so importing the prior two-file component would fail. Root verified its entire prepareFailure function is byte-identical to the accepted fc2096d RED function (SHA256 b29c9db546d13496fccb5ac919a773b740c3eca3ca68c5659c433e6b9b7cd873). The recipient-specific MCPReadService.patch contains only the same approved two-catalog READ_FAILED JSON/nil-sidecar logic, without diagnostics, guidance or unrelated fixtures. The surrounding service is preserved.

Packet directory: `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/t2382-focused-followup-4b4ecf35/`. Two owned fixture patches bound startup to two seconds and completion receipt to eight seconds. Cancellation is checked before a queued blocker enters the original six-second sleep; its defer signals completion. A missed start prevents dispatch and records cleanup failure explicitly. Successful cleanup is required before subsequent MainActor accounting. Coordinator response errors retain the original error after bounded blocker cleanup and bounded unfinished-permit polling. Existing five-second return bounds, invalid-argument ordering, publication and retained-permit assertions remain. Runtime acceptance is pending.

The shared HTTP helper is separately owned by T2383. Its existing 4ddbfc8774aa2bd95da545d14de8065bf12f16f9 component uses async NIO channels and awaited normal/error cleanup. Root verified its parent helper is byte-identical to T2382 4b4ecf35 and exported the exact single-file patch for parent coordination at `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/t2382-shared-helper-reference/manifest.json`; read-only apply check passes. No helper edit or recipient mutation was performed by T63. No runtime job launched while T1734 held the slot.
