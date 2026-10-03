# Isolation integration preparation

Status: original source-only recommendation below is superseded by the parent-delivered exact-base isolation component f7cbb04287062d5c1bf7f3780816d1a9b97eb19f. Parent authorised consuming that component and exclusive dedicated smoke followed by the previously approved presentation/protocol GREEN suites, serially. Preserve original handler/server signatures. T63 integration remains separate. No production launch, MCP activation or live write is authorised.

## Exact checkpoints

T2383 target: clean `feeb7df8e115edcc0139072c08c0968c3ce157dc` on `T-2383/structured-mcp-results`. Common ancestor with the parent-selected T63 source is `201205bd4e786c7f152d8f99006b37da7da888c7`.

Recommended incoming source: immutable T63 Stage A `b500543369ebbd53f01634fa829bf74a8fceabe5`. Parent reports and its foundation handoff records dedicated isolated smoke 1/1 and final Stage A 14 methods/17 executions passing. This is upstream evidence, not verification of the combined T2383 worktree and not modern API delivery.

Isolation component reference: `9ba4297`, cumulative patch `/Users/arjen/Documents/Codex/2026-10-02/task/verification/transit-isolation-component-9ba4297.patch` based on `36f7ee3`.

## Recommended integration

Merge the exact T63 source checkpoint into the T2383 ticket branch after the parent confirms this incoming scope. Do not cherry-pick the isolation patch first, copy TransitApp from containment, or merge the evolving containment branch. The selected T63 checkpoint already contains the component and its narrow read-service compiler fix.

A read-only diff between b500543 and 9ba4297 is empty for TransitApp, Makefile, project.pbxproj, Configuration, shared schemes, Services, isolation runner and smoke tests. Therefore no new App/project adaptation is presently proposed. Any conflict or subsequent adaptation in these files returns to the isolation owner.

The incoming App preserves `MCPReadAppDependencies.make(container:syncActive:)`, one `MCPReadCoordinator(domain: reads.snapshots.domain)`, and that same coordinator in handler/server. It also preserves policy-before-storage selection, isolated counters/sidecars, suppressed automatic MCP startup and the six-model receipt schema. T2383 currently lacks these dependencies; a clean patch application alone would not establish this integrated foundation.

Read-only `git apply --check` of the cumulative patch passed on feeb7df. Legacy read-only merge-tree analysis found only `specs/OVERVIEW.md` changed in both, with two conflict hunks. Retain both tickets' rows and file listings there. T2383 production edits are confined to new Results/Protocol files and their tests; they do not overlap the incoming foundation source. This analysis does not substitute for an actual merge/build.

The modern write-tree merge preview was unable to create its temporary shared Git object under the current sandbox. It performed no merge. A read-only trivial merge-tree preview supplied the conflict analysis instead; no permission setting was changed.

## Ownership and subsequent verification gates

Importing the checkpoint does not transfer ownership. T63 retains all Reads, ordinary snapshot retention and current shared dispatch/schema files until the exact parent handoff; T2384 retains WriteCoordinator and its tests; the isolation owner retains App/project/targets/schemes/entitlements. Modern transport fixtures and separate Results/Protocol code remain T2383-owned.

After local integration and owner review, obtain the parent's exclusive smoke grant. Use the dedicated `test-isolated-host-smoke` target with a fresh private SMOKE_DERIVED_DATA path. Check signed `me.nore.ig.Transit.development` host, absent CloudKit/push/App Group entitlements and actual isolated storage/counter/sidecar evidence before any ordinary focused suite. Shared Transit Debug is the subsequent unit-test scheme; TransitDevelopment is not the unit-test scheme.

Only after that smoke and separate focused grants, verify presentation source f4bd03a (25 declarations/55 runs) and protocol source b6b616e (30 methods/44 runs), preserving existing RED fixtures. Their final application GREEN remains outstanding. No API15 delivery, main merge, push, deployment, production launch or live mutation is implied.
