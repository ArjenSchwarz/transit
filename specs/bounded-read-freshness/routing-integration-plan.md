# Task 12 remainder and staged task 13 integration

Prepared against `54bfe98`, with capability/server RED evidence on `e3812b1`. The parent authorized Stage A source implementation after actual routing/capability RED; no new product approval or T2382 delivery is required for generic routing repair. This document does not claim task 13 GREEN. Actual single-router RED remains `099415e`: four device executions failed after successful compilation. Capability RED ran three failing executions; stopped-server baseline ran eight executions with three failures and five preservation controls passing. Both exclusive test slots were released after drain. Further app jobs require a new grant.

## Stage A: independent bounded routing and lifecycle

The three ordinary covered reads can be integrated without waiting for portfolio modules. Inject one process-lifetime coordinator and its publication domain into `MCPServer`, retaining the existing desired-state reconciliation, graceful `ServiceGroup` shutdown, listener task completion fence and stale-listener generation check. A replacement listener reuses that coordinator. Stop closes read admission and selects terminal fallbacks before listener teardown; generation changes never clear unfinished physical permits. A stale listener callback must not stop a newer generation. Repeated starts on the active port must not invalidate current operations.

The single-read transport seam records the original decoded admission instant and uses an immutable availability/classification snapshot. Prepare timeout, busy and publication-error RPC bytes with the actual request ID outside the common domain. Admit before tool-domain validation or any MainActor hop. The worker calls saved-read preparation, wraps the authoritative tool fragment in the complete RPC response, and offers those final bytes and private publication candidates together. No serialization follows successful publication. Writes and maintenance retain their existing dispatch and receipts; neither receives read freshness metadata.

Implement the already declared `MCPReadCapturedPreparing` on the existing service. Begin the observation window before the policy decision and hold it through saved capture, metadata freeze, async DTO transformation and private reservation preparation. Preserve the operation's original remaining budget. Capture stays synchronous on MainActor inside its history/generation fence; no models escape. Production missing applicability/visibility proof remains unknown/null with refresh unavailable. Retained replay bypasses this fresh-capture path.

The concrete server injection seam should pass the same coordinator to construction and every router generation; constructing a new coordinator in `makeRouter` or `launchServer` would lose the physical-work bound. Existing listener fences remain authoritative for socket release.

Two small interfaces were confirmed as routine task 13 integration choices; neither has runtime binding yet:

- Preallocated operation UUID accepted by single-read admission, with a default UUID for existing callers, to encode machine fallback correlation before admission. Reject an already-live UUID without replacing its entry. The actual JSON-RPC ID remains a separate value.
- An operation-specific physical-completion receipt for deterministic tests. It completes only after worker finalization and private publication cleanup, resumes outside the common lock, and does not turn terminal selection into permit release. Completed-receipt storage must be bounded or caller-owned.

`MCPReadAdmission(operationID:physicalCompletion:)` now declares those caller-owned values. Capability RED at `e3812b1` compiled and ran three failing methods; final acceptance must remove its test-only baseline adapter and call the real coordinator admission overload directly. The callback may run after `unfinishedCount` reaches zero, so tests await both independently with bounded waits. There is no completed-receipt registry.

### Exact direct-coordinator lifecycle fixture plan

Use the existing `MCPReadCoordinator` directly, not a new runtime wrapper. Proposed task 13 plumbing is `MCPServer(toolHandler:readCoordinator:)` and `MCPServer.makeRouter(handler:readCoordinator:)`, both retaining the same injected instance. `TransitApp` constructs one coordinator/domain/launch-fixed monitor/service. Existing `DesiredState`, `serverGeneration`, `ActiveServer`, `ServiceGroup.triggerGracefulShutdown()` and listener-task completion remain responsible for listener reconciliation/socket release.

The additional fixture file is `MCPReadServerCoordinatorLifecycleTests.swift`; it is not supplied or run yet because the injection plumbing is absent. Use existing loopback-port/lifecycle test helpers rather than replacing shutdown fences:

1. Start the actual listener with the injected coordinator and matching ordinary-store domain. Start eight direct admitted workers with unique preallocated IDs and caller-owned physical receipts; each signals start and awaits a release latch. Stop the server, await all eight terminal fallbacks, restart the same listener port, and assert a new operation is busy while old workers remain physical. Release the old latch, await each receipt plus count drain, then assert new-generation work succeeds. Also assert the server/router retained the same coordinator reference, rather than constructing a replacement.
2. Observe the actual first listener generation, restart, then invoke `listenerDidExit` with that recorded old generation. Assert the replacement remains running with admission open; admit and finish current work. The existing unmatched `-1` callback fixture is only a preservation control and cannot satisfy this assertion. A narrow read-only generation inspection seam is sufficient if needed; do not replace lifecycle state or add an independent generation owner.
3. Prepare an ordinary private cursor candidate with the operation ID, signal its prepared state and latch before full RPC encoding. Stop selects preencoded ID-correct fallback; release late preparation and assert candidate never becomes visible, private charge clears exactly once, and the physical receipt follows cleanup. Success counterpart must preserve exact frozen metadata bytes and actual escaped RPC ID in the complete selected response before the common gate.
4. Force outer encoding failure after private reservation ownership exists. Invoke the dispatcher's actual failure-cleanup path, assert its complete preencoded failure has the original RPC ID, zero visible/pending retained charge, and one physical receipt. A fixture encoder may inject this failure; it must not implement a different publication gate or duplicate T2382 retention logic.

These tests must call the actual injected server and real admission overload once implementation exists. An interface-only compile/capability RED is labeled separately; it cannot substitute compiled behavioral lifecycle or final helper acceptance. No sockets/tests are launched without the exclusive slot.

## Remaining task 12 fixtures

These tests use the real coordinator, domain and ordinary retention participant. A fixture helper implements only the tool-level contract; it does not copy portfolio aggregation or reusable-store logic.

| Fixture | Forced ordering and assertion | Acceptance limit |
| --- | --- | --- |
| Captured preparation capsule | Saved fixture with pending UI edit; transform receives one saved view and the exact frozen metadata bytes; its returned fragment has no originating RPC ID. Hold transform while checking original remaining budget declines. | Requires concrete generic preparer for GREEN; fixture helper cannot establish import proof. |
| Private publication and outer encoding | Reserve an ordinary cursor root, latch before full RPC preparation, assert zero visible roots, then encode an escaped/long actual ID and offer. Success bytes reference only the now-published root and contain the original metadata fragment verbatim. | Establishes common foundation boundary, not modern structured encoding. |
| Failure after private preparation | Force outer encoding/preparation failure after reservation creation. Return a preencoded ID-correct failure; no cursor becomes visible, pending accounting clears exactly once, physical receipt completes afterward. | Requires a dispatcher failure/cleanup seam; must not leave unattached reservations. |
| Stop/restart with unfinished work | Latch a prepared worker, stop and restart the same server/coordinator lifetime. Old caller receives fallback; a full set of old physical workers keeps a new caller busy. Release workers, await physical receipts, then admit new-generation work. | Server lifecycle injection needed; existing graceful listener tests still run. |
| Stale listener completion | Replace listener generation, deliver the old completion callback while current read is pending, assert current admission remains open and current result can publish. | Actual server lifecycle acceptance, not standalone coordinator stop/start. |
| Helper rejection/scope | Test helper receives the capsule's same view identity/evidence and exact metadata; typed outside-scope request fails without publishing; selected valid request returns tool-level bytes and private candidates. | Fixture contract only until real T2382 handlers run. |
| Read/write preservation | Separate server/read fixtures exercise existing mutation safety input/output/receipt/revision behavior and maintenance dispatch. Assert no read metadata is added to these responses. | Do not edit T2384 coordinator or its tests. |

Use latches and physical-completion receipts rather than arbitrary cleanup sleeps. Keep each expected compile failure distinct from a compiled behavioral RED. The next focused command and exact suite list will be reported before requesting the exclusive app slot. During the coordinated quiet measurement window, no build, test, typecheck, lint or review CLI runs.

## Stage B: actual T2382 modules

Source integration is now `c123210ac2ed749726391e16b39cfab81fed84f3`: exactly six portfolio-owned production files from `8478b17f554e9d7e93a3dd5b76fd1396f4295d07`, with every hash matching the owner's dependency manifest. Shared wiring, App/project isolation and tests were not replaced. Owner verification at `a3c2a705` passed 54 declarations/61 expanded cases with normal exit/drain; that is separate component evidence, not T63 integrated GREEN. Local lint, syntax and diff checks passed. No integrated app run has been performed.

The confirmed entrypoints return `MCPPreparedToolRead`:

```swift
handlePortfolioSummary(request: MCPPortfolioSummaryRequest,
                       capture: MCPPreparedReadCapture?,
                       operation: MCPReadOperation) throws -> MCPPreparedToolRead
handleSnapshotTaskQuery(request: MCPSnapshotTaskQueryRequest,
                        operation: MCPReadOperation) throws -> MCPPreparedToolRead
```

T2382 supplies requests, definitions/descriptors, aggregation, projection, reusable retention and lifecycle hooks. T63 supplies common construction, generic policy-bound preparation, shared registration and outer encoding. Fresh helpers consume the same capsule and original frozen metadata; snapshot replay uses retained view/policy/fragments without recapture or import wait. Do not add RPC IDs to helper interfaces.

Final actual-module assertions include portfolio read classification and descriptor registration, `query_tasks` snapshot dispatch, declared physical-scope rejection, retained metadata/policy/expiry replay, actual reusable/ordinary participant coalescing and all-or-none publication, and lifecycle invalidation. Copied source or fixture GREEN cannot satisfy these assertions; the delivered component is now an input to Stage B verification.

The owner's prepared router suite at `c8e7ebb` contains four methods, including the 2,375-task case. It depends on `MCPPortfolioFixture.swift` and existing model-container/counter/fallback/HTTP test helpers; it has not been copied here. Its current request helper omits the protocol-version header, so the fixture owner must align that boundary with T2383's delivered modern adapter before final combined acceptance. Source/presentation and exact opaque-metadata lexical preservation require their separate modern acceptance assertions. Source delivery removes the implementation prerequisite; a parent-directed fixture handoff and exclusive test grant remain necessary for local Stage B verification.

## Stage C: modern wire ownership and final acceptance

After a stable bounded integration revision and explicit shared-file transfer, T2383 is the sole modern adapter writer. Modern protocol/header/envelope/availability validation precedes read admission; tool-domain validation stays bounded. Its frozen result encoder preserves original text, `isError`, source/presentation and exact `_meta`, then adds the current RPC ID before the same terminal gate. Expanded fragments and retained backing are charged without duplicate ownership.

Modern production rejects arrays. Mixed/all-notification legacy task text is superseded by the approved modern protocol; existing batch coordinator fixtures remain historical component evidence. T63 adds no dual-era production path. Modern discovery/subscriptions, array rejection and final wire contract are T2383 acceptance. Final combined bounded routing and actual-module tests run after that adapter delivery.

Task 13 is complete only after the required actual-module and final adapter acceptance. Intermediate Stage A GREEN must be labeled accordingly. Ownership remains the committed `integration-ownership.md`; this plan changes no file owner and authorizes no source handoff.
