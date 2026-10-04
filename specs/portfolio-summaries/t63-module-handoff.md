# T-2382 verified module handoff to T-63

## Verified source and isolation boundary

Ticket branch: `T-2382/portfolio-summaries`; worktree: `/Users/arjen/Documents/Codex/2026-10-03/task-2/transit`.

Pure projection/parser source is `4e1bfd38dc6562d3e70178babf5e6bb51bd9e1c9`. The exact approved isolation component `870a4baf6bf6d2d117e1c9c3a4446fd3fc431524` was cherry-picked as `0aef5c4a5bc0c5f2ae2a6c87a65e42ee455c3b5c`, with no MCP diff. On that clean checkpoint, signed development-host preflight plus isolated projection GREEN passed 45 cases, zero failures/skips. Task-9 evidence and completion are committed in `36a8000`. Earlier focused aggregation/window passed 54/54; corrected retention passed 29/29. These are focused module proofs, not final combined handler/transport acceptance.

Preserve the approved development isolation boundary when consuming MCP files. Do not merge an alternate App/project component, launch production, or perform live Transit mutations. T-2382 holds no heavy test slot after this checkpoint.

## Delivered module seams

- `PortfolioSummaryService.summarize(view: CapturedReadView, window: CompletionWindow) throws -> PortfolioSummary` aggregates complete declared scope from physical identities without live model access.
- `MCPPortfolioSummaryRequest.parse(_:)` supplies initial window/limit/selector/policy, snapshotId-only replay, and cursor/policy continuation.
- `MCPSnapshotTaskQueryRequest.parse(_:)` supplies strict captured snapshot options or reusable continuation; no project names, comments, arbitrary filters, scope expansion or policy override on initial task projection.
- `MCPPortfolioProjection.query(root: RetainedView, request: MCPSnapshotTaskQueryRequest) throws -> EncodedSnapshotTaskPages` returns private first/continuation page bytes, cursors, original metadata bytes, snapshot identity and original retention deadline. Status filtering uses effective status; full output retains canonical captured r1 while omitting comment bodies.
- `RetainedView` retains the shared `CapturedReadView`, exact `frozenMetadataBytes`, original window/request and encoded first summary page. `MCPReusableSnapshotStore` participates in the existing sole publication domain, supports staged create/append and aggregate publication, and preserves requested-root identity across unrelated updates. Its encoded capture charge must include frozen metadata and retained encoded backing.

## Shared preparation and next binding

The confirmed proposed tool-level own entrypoints are:

```swift
handlePortfolioSummary(request: MCPPortfolioSummaryRequest,
                       view: CapturedReadView,
                       operation: MCPReadOperation) throws -> MCPPreparedToolRead
handleSnapshotTaskQuery(request: MCPSnapshotTaskQueryRequest,
                        view: CapturedReadView,
                        operation: MCPReadOperation) throws -> MCPPreparedToolRead
```

Those task-12 helpers are not delivered yet: current own handler files remain explicit scaffold errors with old signatures. Do not wire them as implemented handlers or claim public integration. T-63 must supply the exact approved `MCPReadCapturedPreparing`/`MCPPreparedReadCapture`/`MCPPreparedToolRead` and generic reusable-validation revision before T-2382 binds these interfaces. Previously inspected `0ff9876` and corrected `dc85eab` have not been consumed here.

Initial capture preparation must pass the complete declared-scope immutable view, original frozen metadata bytes and the same admitted operation through private aggregation/encoding/staged retention. T-63 retains and validates its observation through that transform under the original budget, then encodes the actual-request-ID outer envelope and selects publication/result together. Replay and continuation bypass live capture and reuse original bytes/identity/expiry. Do not broaden selected project scope because foreign identity closure exists; minimal foreign milestone selected JSON remains `{milestoneId,name}` with full typed identity/relationships/status/timestamps.

T-2383's agreed ordered/validated metadata-fragment boundary still needs its exact delivered revision before final binding. Preserve unknown metadata bytes without dictionary/Double round trips; charge all retained encoded backing. Shared registry/dispatch/read-only classification/lifecycle changes belong only to T-63. Final combined acceptance, full regression and pre-push review/Pulsar remain pending.

## Descriptor delivery

Source checkpoint `0b730577d5aac2f3d63705a2d0c7ac0a1ffdc0d3` plus reviewed wording correction `11502863f9e749a12aea0563041b408694a5d67f` delivers `MCPPortfolioToolDefinitions` in its own file:

- `queryProjectSummaries: MCPToolDefinition` for `query_project_summaries`, with mutually exclusive no-selector/projectId/project initial branches, snapshotId-only replay and continuation. Every branch rejects additional properties.
- `snapshotTaskQueryInitialSchema: JSONSchema` for the deliberately restricted retained-snapshot `query_tasks` branch.
- `reusableContinuationSchema: JSONSchema`; merge/replace the common query_tasks cursor branch rather than appending an overlapping oneOf alternative. Preserve ordinary cursor dispatch/family behavior.
- `snapshotTaskQueryDescription: String` to append to the existing ordinary tool description while retaining ordinary raw-status filtering and existing field/order behavior.

Lint passed with zero violations in 447 files; strict Swift 6 typechecking used the full actual MCPTypes.swift and MCPReadMetadata.swift, without extraction or stubs. Peer review found no other concrete parser/schema mismatch after correcting advertised field spellings, failure-category case and response-availability wording. No app compilation or registration/route test was performed for this new descriptor.

Current shared JSONSchemaProperty lacks minimum/maximum, a boolean const and default. T-63 owns adding/binding `minimum:1`, `maximum:100` for limits, `const:false` for snapshot includeComments and `default:"refresh_if_needed"` for initial policy to encode these constraints machine-readably. Source currently states these constraints in descriptions and the already verified parsers enforce them. Do not claim full strict-schema registration complete until the shared owner resolves this limitation. Task 10 stays in progress; task-11 preparation cannot count as actual compiled behavioral RED before the dependency is delivered and a serialized test slot is granted.

## Initial-helper frozen-byte binding requirement

The proposed view/operation signatures above predate delivery of the frozen-metadata capsule. A typed view alone does not carry the capsule's original metadata bytes. Before binding task 12, coordinate an exact initial-summary entrypoint that also receives `MCPPreparedReadCapture` or explicit `frozenMetadataBytes: Data`; do not re-encode `view.metadata` to manufacture retained bytes. The agreed transform already receives the capsule and same operation, so the bridge must forward its bytes into the own helper. Snapshot replay/query can obtain original bytes from the existing retained root and must bypass live capture. No signature change or shared binding has been applied at this checkpoint.

## Task-11 source preparation

`c02987bbdfc1a6724e3726c6f383db5ff809f84f` adds only `MCPPortfolioHandlerTests.swift`: 15 public-dispatch test declarations covering advertised schemas, strict arguments/selectors, empty/populated metadata, frozen replay/continuation, snapshot effective-status/revision reconciliation, captured scope, cursor families, policy, fallback read classification and ordinary query compatibility. Task 11 stays pending because task 10 is not complete. Syntax and full lint pass (zero violations across 448 files); peer review found no concrete fixture/API or false-expectation defect. Standalone typechecking against the earlier isolated compiled app module stopped before checking the source at missing `_AtomicsShims`; app compilation and behavioral RED remain unverified.

Required fetch/coherence/serialization fault-injection assertions await a delivered public preparation seam; no mock shared API was invented. Exact opaque metadata-byte preservation at the wire likewise needs the delivered T-2383 fragment boundary/capsule fixture. Focused target after dependency delivery and a new isolated test slot: `TransitTests/MCPPortfolioHandlerTests`. Do not use one-step app-host testing without attesting the signed host, generated xctestrun and startup guard. No heavy job ran for this preparation.

## Agreed ABI and real-source binding checkpoint

This section supersedes the earlier view-only and case-specific proposals. Parent/T-63 agreed, and own source `166752b30ca2d4ad33d5a420fff774caa046a205` now declares exactly:

```swift
nonisolated func handlePortfolioSummary(
    request: MCPPortfolioSummaryRequest, capture: MCPPreparedReadCapture?,
    operation: MCPReadOperation
) throws -> MCPPreparedToolRead
nonisolated func handleSnapshotTaskQuery(
    request: MCPSnapshotTaskQueryRequest, operation: MCPReadOperation
) throws -> MCPPreparedToolRead
```

Initial summary receives the direct capsule from `prepareCapturedRead`; replay/continuation receive nil and must read their own retained root, original bytes, identity and expiry. Snapshot tasks obtain that retained root themselves. All bodies still throw `notImplemented`: this is the task-10 interface seam, not task-12 GREEN. There is no separate retained-summary helper.

The verified shared preparation at `b500543` was consumed as the MCP-only 19-file delta from the existing `a694c27` shared base, committed `8e8d855`. The exact schema definition `f4e29556feb36dec62e8ebeb7f20b5110a5b6f4b` was cherry-picked as `591555f`, and exact internal failure mapper `1b2e813f154b8dbfd542cb63d4bb66bdac669e1c` as `346ceda`. No App/project/isolation source was imported. Descriptor `166752b` now encodes both limit ranges, includeComments const false and the initial policy default using the sole shared schema definition; continuation has no default. Actual shared-type descriptor typecheck, helper parsing and lint passed.

Updated own tests `ebaa0448ba023210ca7b8992bfd1536b66efad1e` contain 16 declarations / 18 expanded source cases. Covered calls use actual `MCPBoundedReadDispatcher.classify`/`response` and authoritative Data; they require common classification instead of inventing it. Direct handler.handle bypasses admitted preparation in b500543 and is used only for noncovered tools/list. Test-local memory fixture binds the real saved capture builder, inactive monitor, ordinary snapshot store, service and coordinator sharing one publication domain. Typed storage/serialization/coherence source failures are tested inside the admitted worker. Nonquery failure text is plain message; assertions use the external actual category and never assume unencoded READ_FAILED or outer-encoding fallback. Machine schema constraints are asserted. Syntax, lint (zero/460) and peer source review pass; no app compilation/runtime proof is claimed.

Task 10 still awaits the owner's portfolio registration, shared dispatch/reusable-store constructor and lifecycle component. Task 11 remains pending; this bound source is preparation only until that dependency and an explicit isolated test grant arrive. Modern/API15 fragments remain a final integration dependency, not fabricated runtime coverage. The prepared runner under `t2382-review-evidence/handler-preparation/handler_runner.py` accepts an explicitly reviewed full source revision, fresh revision-specific artifacts and only the handler suite; it attests isolation-critical files against 0aef5c4, signing, mode, exact host and startup guards before launch. No runner phase was executed.

## Verified implemented helper handoff — 2026-10-04

This checkpoint supersedes every earlier scaffold/not-implemented, pending-task-10/11, and proposed view-only ABI instruction above. Tasks 10–12 are complete; final task-13 HTTP/API15 acceptance and task-15 full regression remain pending.

Exact tested source: `a3c2a705a2dc73958c12c9ce0ff6dc2355b80794`. The unchanged reviewed runner SHA256 is `90c3c7cfb1890c8c1213efc70b0198735a5511b216537d50273b173b35a2a9d3`. Fresh signed development host and restricted xctestrun preflight passed. Build and test exited zero. All three selected suites passed: 54 declarations, 61 expanded device cases, zero failures/skips/expected failures. Physical host and process group drained normally. Independent requirements-critic review verified evidence, ownership and exact ABI; no remaining own-source blocker was found. Previous `b31841c` assertion failure and teardown timeout remain preserved as failed evidence, without a GREEN claim or inferred timeout cause.

### Consume only this new portfolio-owned production component

`8478b17f554e9d7e93a3dd5b76fd1396f4295d07` changes exactly these six source files and can be consumed independently of shared T-63 registration and App/project isolation changes:

- `Transit/Transit/MCP/MCPToolHandler+PortfolioSummary.swift`
- `Transit/Transit/MCP/MCPToolHandler+SnapshotTaskQuery.swift`
- `Transit/Transit/MCP/MCPReusableSnapshotStore.swift`
- `Transit/Transit/MCP/MCPPortfolioReadEncoding.swift` (new)
- `Transit/Transit/MCP/MCPPortfolioCaptureCharge.swift` (new)
- `Transit/Transit/MCP/MCPReusableSnapshotReadPin.swift` (new)

The actual agreed entrypoints remain:

```swift
nonisolated func handlePortfolioSummary(
    request: MCPPortfolioSummaryRequest, capture: MCPPreparedReadCapture?,
    operation: MCPReadOperation
) throws -> MCPPreparedToolRead
nonisolated func handleSnapshotTaskQuery(
    request: MCPSnapshotTaskQueryRequest, operation: MCPReadOperation
) throws -> MCPPreparedToolRead
```

Initial summaries consume the direct immutable capsule with authoritative frozen metadata bytes. Replay, continuation and snapshot task projection use retained values without live capture. Encoding and all retained backing are charged before staged publication. Identity/deadline pins survive through the final sole-domain gate; pins and append mutations compact together without a guard-only store swap. Existing T-63 wiring constructs the reusable store in the same publication domain and forwards these signatures; no shared wiring edit belongs in this component.

T-63 already contains its own `226db40` bridge, `1100799` expiry-family mapper, `7a2f4de` test compile correction, and `eb3d9dd` selector-category correction, consumed locally as `e13fa6f`, `deead79`, `cd20767`, and `f60c43b` respectively. Do not cherry-pick these shared dependencies back into T-63. Descriptor `42d2d82` wording is already consumed there as `6de04f6`; its source bytes match. The earlier pure modules are already present through T-63's `990391c` module import.

Owner tests may be consumed separately: exact `a3c2a705` version of `MCPPortfolioHandlerTests.swift` (requires `MCPPortfolioFixture.swift` and earlier owner fixtures), and `d67c09a` adds `MCPReusableSnapshotReadPinTests.swift`. Reuse existing store regressions. The final ordinary-query assertion correction `a3c2a705` changes only `idea` to raw `legacy-status`; canonical baseline `201205bd` and requirements 2.4–2.5 independently verify this oracle. It does not change ordinary production behavior.

Local result evidence: `../t2382-review-evidence/handler-preparation/green-a3c2a705a2dc73958c12c9ce0ff6dc2355b80794/`. A source/hash/dependency manifest is prepared beside it for parent-directed selective integration. No routine external delivery, live writes, push, merge or deployment is authorized. The heavy slot is released; T-1734 owns it. Task-13 source preparation can proceed, but execution requires parent scheduling and final combined transport acceptance requires API15.

## Corrected actual-router fixture handoff — 2026-10-04

Current-foundation router evidence is exact `b4c104e76a482562bc8eae2ae9f54a6e5712ffc5`: fresh guarded build and signed development preflight passed; `MCPPortfolioIntegrationTests` passed 4/4, zero failures/skips, normal exit 0, owned host/process group fully drained. Independent review verified the evidence and source correction. This is not final modern/API15 acceptance.

The test-only handoff consists of `c8e7ebb6ed168881b00f3d2d38d9943b7e6434fa` (new integration test file) followed by `b4c104e76a482562bc8eae2ae9f54a6e5712ffc5` (only `import HTTPTypes` and explicit `@MainActor` on nested Environment; assertions unchanged). Alternatively take the exact tested version of `Transit/TransitTests/MCPPortfolioIntegrationTests.swift`. Also supply `Transit/TransitTests/MCPPortfolioFixture.swift` from the same revision if missing; T-63's inspected worktree did not yet contain that fixture. Existing central in-memory TestModelContainer, MCPHTTPTestHelpers/MCPTestHelpers and FallbackOutcomeFixture remain dependencies. No App/project, shared-source or spec-doc changes are required for this test handoff.

Runner SHA256: `10e02c5f2223b40f330546299a54d85961811a455e975266715f536e91f68f8f`. Local evidence lives under `../t2382-review-evidence/handler-preparation/green-b4c104e76a482562bc8eae2ae9f54a6e5712ffc5/`; a `verified-router-fixture-handoff-b4c104e76a482562bc8eae2ae9f54a6e5712ffc5.json` manifest alongside it contains exact source hashes and dependency identity. The initial compile-failed c8e7 attempt is preserved separately and executed zero tests. The volume assertion accepts complete reconciliation or approved typed timeout/capacity; its outcome branch was not separately logged, so this evidence does not independently establish that the large fixture returned full success.

Task 13 remains in progress: saved-only reads, mutation-frozen reconciliation, lifecycle invalidation and bounded volume behavior now have actual-router baseline PASS evidence. Expiry boundary preparation can proceed independently. Actual portfolio-router lingering/busy/late publication, final encoding/publication faults, restart/write-receipt integration, opaque metadata bytes and final API15 transport/session/security acceptance remain outstanding as applicable. Task 14 stays pending: the four tests revealed fixture compile issues but no owned production defect; its combined acceptance prerequisite remains unmet. Task 15/full pre-push/Pulsar also remain pending. No completion is inferred from the current-foundation pass.

## Verified actual-router expiry handoff — 2026-10-04

Consume only `ee053269f83153d136a4613db296bd735b9c2ffc`, adding `Transit/TransitTests/MCPPortfolioRouterExpiryTests.swift`. Source SHA256 `5720cf238e5150214b69f8c6551210c2ac3b0a2de0c37dd11405c04294618746`. It depends on the earlier fixture/helpers handoff, leaves the four verified integration tests unchanged, and includes no shared or App/project source. Fresh guarded build and signed development preflight passed; restricted serial execution passed 2/2, zero failures/skips, normal exit 0, all owned processes physically drained.

The two tests verify original frozen root/cursor responses just before the exact five-minute deadline, `INVALID_SNAPSHOT`/`INVALID_CURSOR` at expiry, no live recapture and accounting after physical worker drain. They use existing pin-only replies at the advanced retention clock, so they do not invent admission time or stage an append against a simulated future operation deadline. Local evidence: `../t2382-review-evidence/handler-preparation/green-ee053269f83153d136a4613db296bd735b9c2ffc/`; exact manifest `verified-expiry-handoff-ee053269f83153d136a4613db296bd735b9c2ffc.json` is beside the run directory. Runner SHA256 `79318c12e60320ad440bd6008908dd0981f941028a27da8aa2652953531e9fce` preserves the reviewed isolation/cleanup guards with only the suite selector changed.

Task 13 remains in progress and task 14 remains pending. This extends current-foundation coverage and does not establish final modern/API15 transport, opaque metadata, restart/write receipts or actual portfolio-router lingering/busy/late-publication acceptance. The heavy slot is released; no further heavy execution is authorized without parent scheduling.
