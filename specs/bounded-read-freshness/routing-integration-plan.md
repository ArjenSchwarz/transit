# Task 12 remainder and staged task 13 integration

Prepared against `54bfe98`. This is an implementation handoff proposal, not a task 13 implementation or verification claim. The actual single-router RED remains `099415e`: four device executions failed after successful compilation. No further app job is authorized at this checkpoint.

## Stage A: independent bounded routing and lifecycle

The three ordinary covered reads can be integrated without waiting for portfolio modules. Inject one process-lifetime coordinator and its publication domain into `MCPServer`, retaining the existing desired-state reconciliation, graceful `ServiceGroup` shutdown, listener task completion fence and stale-listener generation check. A replacement listener reuses that coordinator. Stop closes read admission and selects terminal fallbacks before listener teardown; generation changes never clear unfinished physical permits. A stale listener callback must not stop a newer generation. Repeated starts on the active port must not invalidate current operations.

The single-read transport seam records the original decoded admission instant and uses an immutable availability/classification snapshot. Prepare timeout, busy and publication-error RPC bytes with the actual request ID outside the common domain. Admit before tool-domain validation or any MainActor hop. The worker calls saved-read preparation, wraps the authoritative tool fragment in the complete RPC response, and offers those final bytes and private publication candidates together. No serialization follows successful publication. Writes and maintenance retain their existing dispatch and receipts; neither receives read freshness metadata.

Implement the already declared `MCPReadCapturedPreparing` on the existing service. Begin the observation window before the policy decision and hold it through saved capture, metadata freeze, async DTO transformation and private reservation preparation. Preserve the operation's original remaining budget. Capture stays synchronous on MainActor inside its history/generation fence; no models escape. Production missing applicability/visibility proof remains unknown/null with refresh unavailable. Retained replay bypasses this fresh-capture path.

The concrete server injection seam should pass the same coordinator to construction and every router generation; constructing a new coordinator in `makeRouter` or `launchServer` would lose the physical-work bound. Existing listener fences remain authoritative for socket release.

Two small interfaces need confirmation before source implementation:

- Preallocated operation UUID accepted by single-read admission, with a default UUID for existing callers, to encode machine fallback correlation before admission. Reject an already-live UUID without replacing its entry. The actual JSON-RPC ID remains a separate value.
- An operation-specific physical-completion receipt for deterministic tests. It completes only after worker finalization and private publication cleanup, resumes outside the common lock, and does not turn terminal selection into permit release. Completed-receipt storage must be bounded or caller-owned.

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

After clean module delivery, wire the confirmed signatures returning `MCPPreparedToolRead`:

```swift
handlePortfolioSummary(request: MCPPortfolioSummaryRequest,
                       view: CapturedReadView,
                       operation: MCPReadOperation) throws -> MCPPreparedToolRead
handleSnapshotTaskQuery(request: MCPSnapshotTaskQueryRequest,
                        view: CapturedReadView,
                        operation: MCPReadOperation) throws -> MCPPreparedToolRead
```

T2382 supplies requests, definitions/descriptors, aggregation, projection, reusable retention and lifecycle hooks. T63 supplies common construction, generic policy-bound preparation, shared registration and outer encoding. Fresh helpers consume the same capsule and original frozen metadata; snapshot replay uses retained view/policy/fragments without recapture or import wait. Do not add RPC IDs to helper interfaces.

Final actual-module assertions include portfolio read classification and descriptor registration, `query_tasks` snapshot dispatch, declared physical-scope rejection, retained metadata/policy/expiry replay, actual reusable/ordinary participant coalescing and all-or-none publication, and lifecycle invalidation. Fixture GREEN cannot satisfy these assertions. Missing module delivery blocks Stage B acceptance only, not Stage A generic routing repair.

## Stage C: modern wire ownership and final acceptance

After a stable bounded integration revision and explicit shared-file transfer, T2383 is the sole modern adapter writer. Modern protocol/header/envelope/availability validation precedes read admission; tool-domain validation stays bounded. Its frozen result encoder preserves original text, `isError`, source/presentation and exact `_meta`, then adds the current RPC ID before the same terminal gate. Expanded fragments and retained backing are charged without duplicate ownership.

Modern production rejects arrays. Mixed/all-notification legacy task text is superseded by the approved modern protocol; existing batch coordinator fixtures remain historical component evidence. T63 adds no dual-era production path. Modern discovery/subscriptions, array rejection and final wire contract are T2383 acceptance. Final combined bounded routing and actual-module tests run after that adapter delivery.

Task 13 is complete only after the required actual-module and final adapter acceptance. Intermediate Stage A GREEN must be labeled accordingly. Ownership remains the committed `integration-ownership.md`; this plan changes no file owner and authorizes no source handoff.
