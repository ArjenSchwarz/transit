# T-1734 independent migration-test isolation integration

Status: containment delivered the narrower isolation-only `3194e5a64dedb004dbfca3666bf590a552b676ee` on T-1734 base `594c549`; consumed as `e1c1ac4`. No app build/host run or shared ownership transfer occurred. The source comparison below records the initial integrated-envelope proposal; the owner-delivered component is the selected integration.

## Exactly what task1 needs

The prepared `TaskLinkMigrationTests` imports Foundation, SwiftData, Testing and Transit. Its functional dependencies are the existing six models (`Project`, `TransitTask`, `Comment`, `Milestone`, `SyncHeartbeat`, `MCPWriteReceipt`) and `TestModelContainer`'s default/custom-schema initializers. All exist at base `201205bd`; those models and `TestModelContainer.swift` have no diff between that base and `b500543`.

The fixture does **not** call T-63 capture/freshness/publication, T-2382 portfolio/reusable views, T-2383 result encoding/protocol, or T-2384 batch/coordinator policy APIs. It can run its initial capability RED without all four feature branches merging. Future graph mutation/read integration remains separately dependent on those foundations and feasibility gates.

Its runtime host nevertheless constructs the application. The isolated App startup at the verified checkpoint binds `MCPReadAppDependencies.make`, `MCPReadCoordinator`, `MCPToolHandler(readService:readCoordinator:)` and `MCPServer(readCoordinator:)`. Taking only App/project/isolation files onto the old base leaves that transitive startup dependency missing. A custom isolation-only App rewrite would be new unverified owner work; an old containment App copy must not replace the integrated read plumbing.

## Compared immutable source

| Checkpoint | Role / finding |
| --- | --- |
| `594c54987146b39257f26b1d152999fb452e8f6b` | Current T-1734 checkpoint; only production-tree difference from main base is new migration test source. |
| `201205bd4e786c7f152d8f99006b37da7da888c7` | Exact common ancestor of T-1734 and verified T-63 component. |
| `b500543369ebbd53f01634fa829bf74a8fceabe5` | Verified integrated Stage A source, already consumed by T-2383; includes development isolation plus required read startup plumbing. Upstream smoke/routing evidence is not T-1734 combined-source verification. |
| `9ba4297` | Containment's cumulative verified component. App, Services, Configuration, project/schemes, Makefile, isolation runners and smoke fixture are byte-equivalent to `b500543`; no App/project adaptation is proposed. This alone is not the source dependency closure on the old base. |

Read-only `git merge-tree 201205bd HEAD b500543` reports only `specs/OVERVIEW.md` changed on both branches, with two conflict hunks. Preserve both rows and both file lists. The prepared migration test has no incoming overlap. The local preview is `/tmp/t1734-b500543-merge-preview.txt`; it performed no merge.

## Selected owner-delivered integration

Containment supplied the isolation-only adaptation from established `9ba4297` wiring as `3194e5a64dedb004dbfca3666bf590a552b676ee`, based exactly on T-1734 `594c549`. The parent selected this component instead of the initial full `b500543` envelope proposal. It preserves T-1734's existing MCP/read constructor plumbing and avoids absent T-63 interfaces. The original-base App adaptation, project/target/scheme/entitlement changes and startup guards were applied by their owner; no whole App blob replaced the current source.

Consumed at `e1c1ac4`; all delivered manifest hashes outside the fixture-only lint correction match. Models, TestModelContainer, MCP/read/write sources and the migration fixture were untouched by the component. Existing graph foundation ownership remains intact. Fixture-only lint correction is `d2cc0c6`; branch-local development configuration guard and full strict lint pass (406 files, zero violations). These are source checks, not branch-local runtime verification.

Preserve policy resolution before storage, disabled CloudKit counter construction, isolated sidecars, suppressed automatic MCP startup and the six-model receipt schema. No full T-63 or modern adapter integration is implied. Task1 can exercise its independent model/schema/disk-control capability checks on this host; later graph integration keeps its own foundation gates.

## Concrete next isolated job

T-2383 currently owns the exclusive heavy slot. After owner integration, request a slot for a fresh dedicated isolation smoke, fresh shared Transit Debug build containing `TaskLinkMigrationTests.swift`, signed-host/xctestrun preflight, then **only** `TransitTests/TaskLinkMigrationTests` on macOS serially. Use private fresh DerivedData/result paths and locked package versions. The smoke must verify `me.nore.ig.Transit.development`, no CloudKit/push/App Group entitlement, memory-only host persistence, disabled counter adapters and private sidecars. `TransitDevelopment` is not the unit-test scheme.

`verification-readiness.md` contains the exact guarded offline, signed-host and focused migration commands. Helper checkpoint `b9d65b9e483ea59d65ed458851132184dab1331f` adds branch-local signed artifact/xctestrun checks; it has not executed.

Use a new unused result path for any necessary rerun. Expected source enumeration is two declarations/three expanded cases; inspect xcresult and reject zero tests/compile failure as behavioral RED. Missing link entities should produce honest registration-capability RED; the disk control proves saved observation only. Closed-store process-separated migration, development CloudKit verification and complete task1 coverage remain outstanding, so task1 stays incomplete even if this initial job yields the expected failures.

Live Transit mutations, client activation, production schema promotion and deployment remain held. Reports stay local; owner coordination goes through the parent because this execution context exposes no callable thread-messaging tool.
