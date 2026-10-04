---
references:
    - specs/portfolio-summaries/requirements.md
    - specs/portfolio-summaries/design.md
    - specs/portfolio-summaries/decision_log.md
---
# Portfolio summaries implementation tasks

- [x] 1. Define portfolio interfaces and deterministic captured-view fixture types <!-- id:tn4py0x -->
  - Types/interfaces only: add portfolio result/window/request/projection interfaces in Transit/Transit/MCP and Services/PortfolioSummaryService.swift, nonfunctional typed store/publication interfaces in MCPReusableSnapshotStore.swift and handler entry points in MCPToolHandler+PortfolioSummary.swift/+SnapshotTaskQuery.swift, plus Transit/TransitTests/MCPPortfolioFixture.swift. Use signatures/test seams and explicit not-implemented outcomes so tests compile and fail behaviorally; no aggregation/store/handler logic in scaffolding.
  - Consume T-63 CapturedReadView, ReadCaptureMetadata, ReadCaptureScope.wholePortfolio/projects([LocalRecordKey])/selectedQuery, completePortfolio completeness, MCPRetainedViewSource and MCPReadPublicationDomain; no duplicate DTO/fence/timer. Reusable views reject selectedQuery and retain the same typed scope.
  - Parent supplies the T-63 FOUNDATION revision rooted in merged T-2380 201205bd and implementing approved T-63 5639c40 contracts. T-63 proves admission/capture/transport/publication seams with minimal fixture adapters/test doubles before T-2382 modules; this foundation handoff must not wait for T-2382 final integration. T-63 alone edits MCPServer.swift/lifecycle, MCPToolHandler.swift, MCPToolDefinitions.swift, MCPTypes.swift, shared capture/freshness/publication/read paths. No T-2380 worktree edits.
  - Fixture carries physical relationships, raw/effective statuses, canonical comment-covered r1 tokens/full task JSON and comment evidence. Agree fixture/protocol sketches through parent before binding shared interfaces.
  - Task7 replaces store seams and task12 replaces handler seams; task10 can compile registered signatures before handler RED assertions. No unreachable helper or shared-file edits; T-63 only registers these agreed signatures.
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [6.1](requirements.md#6.1), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7)
  - References: design.md

- [x] 2. RED: add saved-capture and real transport deadline risk-gate tests <!-- id:tn4py0y -->
  - Add Transit/TransitTests/MCPPortfolioReadFoundationTests.swift reusing T-63’s app-router/capture harness and adding portfolio-specific assertions: assert saved multi-entity capture, exclusion/preservation of pending UI edits, import/history mutation rejection, empty-store sentinel, foreign/unavailable fence failure and unknown freshness when store correlation is unproven.
  - Write automated Hummingbird admission-to-encoded-transport-availability assertions <=5s for individual POSTs including slow encode and blocked MainActor; generic component aggregation coverage remains internal and application-level write receipts remain protected. Test cached/default refresh, <=2s wait and 30s recent threshold.
  - Automated 2,375-task fixture with comment-covered revisions tests complete declared-scope capture and canonical revision encoding or typed deadline/capacity failure before aggregation exists; task13 adds actual summary totals/reconciliation, with no partial-success counts. Eight lingering physical workers across restart, ninth busy, exactly-once outcomes/no late publications. New missing-behavior assertions must demonstrate RED before correction; already implemented T-63 assertions may pass and must be recorded as verified baseline, never intentionally broken; standalone prototype is supporting evidence only.
  - All three design risk verification paths are this executable gate. Reserve Xcode27/shared simulator slot through parent; no concurrent heavy run. Test code may be prepared before slot, execution waits.
  - Use foundation-only synthetic read descriptor and minimal prepared-result/publication test double in the reused T-63 harness. It exercises real admission/capture/final encoding/transport availability without depending on summary handlers, reusable store or T-63 remaining ordinary-read conversions. This is the early risk gate, not final cross-ticket acceptance.
  - Blocked-by: tn4py0x (Define portfolio interfaces and deterministic captured-view fixture types)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.4](requirements.md#6.4), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: design.md

- [x] 3. GREEN: integrate T-63 read foundation into the risk harness and pass the gate <!-- id:tn4py0z -->
  - Wire task2 portfolio-specific fixtures to the actual T-63 foundation router/coordinator/capture provider using minimal test adapters; add only T-2382 fixture/harness adapters. T-63 supplies this foundation revision after its own independent risk proof; it does not await tasks7/12. Route any shared production fix to T-63 through parent; do not bypass failed assertions.
  - Run task-2 automated tests in coordinated Xcode27 slot, verify encoded responses and saved-only behavior with canonical r1 capture. If make fails, use available Xcode MCP; currently none exposed, report exact blocker and retain Xcode27 rather than downgrade.
  - Do not complete this gate without actual app-level passes. If fence/timing/volume risk invalidates approved design, stop dependent work, prepare concrete correction and surface new approval through parent. No partial-success or relaxed five-second guarantee.
  - After this foundation gate passes, tasks4/6 proceed while T-63 completes remaining read paths in parallel. Return T-2382 descriptor/store/helper integration handoff at tasks10/12; full two-ticket acceptance waits both at task13. No circular dependency between foundational proof and final integration.
  - Blocked-by: tn4py0y (RED: add saved-capture and real transport deadline risk-gate tests)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.4](requirements.md#6.4), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: design.md

- [x] 4. RED: add aggregation, window and identity property tests <!-- id:tn4py10 -->
  - Add Transit/TransitTests/PortfolioSummaryServiceTests.swift with all eight zero buckets/derived totals, empty projects/milestones, terminal and unknown raw milestone statuses, idea fallback, [start,end) edges, offsets/0–3 fractional digits and strict invalid timestamps, restored terminals/missing dates.
  - Use deterministic seeded generated fixtures and independent reference filters: sums equal physical records, valid milestone+unassigned+invalid partitions reconcile, duplicate names/display IDs never merge, <=10 stable diagnostic samples/exact completeness, orphan counts and UUID ambiguity into scope vs unrelated corruption.
  - Assert all five activity kinds, null evidence, lexical tie-break and milestone-only activity; summary payload never contains task descriptions/metadata/comment bodies. Tests initially fail against interface-only service.
  - Blocked-by: tn4py0x (Define portfolio interfaces and deterministic captured-view fixture types), tn4py0z (GREEN: integrate T-63 read foundation into the risk harness and pass the gate)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5)
  - References: design.md

- [x] 5. GREEN: implement dedicated summary service and completion-window parser <!-- id:tn4py11 -->
  - Implement Transit/Transit/Services/PortfolioSummaryService.swift and MCP/MCPPortfolioSummaryRequest.swift window value/parser to pass task4; pure Sendable captured-value computation, deterministic physical-key indexes, effective statuses and exact bounded diagnostics.
  - Validate project selector/scalar syntax in parser but require selector resolution inside T-63 fenced capture; do not resolve live names before capture. No store fetch, identity repair, mutation or actor-dependent aggregation.
  - Check cancellation/deadline between chunks without treating cooperative cancellation as deadline guarantee; preserve declared physical scope and required identity closure. Complete task4 property suite before handler integration.
  - Blocked-by: tn4py10 (RED: add aggregation, window and identity property tests)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5)
  - References: design.md

- [x] 6. RED: add reusable retention and aggregate publication race tests <!-- id:tn4py12 -->
  - Add Transit/TransitTests/MCPReusableSnapshotStoreTests.swift with injected monotonic clock, publication domain and retirement probes: eight views/16MiB charged root+pages, pending reservation accounting, append bytes only, no live eviction, five-minute original expiry/no extension.
  - Test two same-store creates/appends in one internal aggregate preserve both under ONE candidate/version/reservation and one swap; all stores validate before any commit. Stale CAS, capacity/root expiry/lifecycle/encoding/deadline rejection roll back once and error bytes contain no unpublished IDs.
  - Race simultaneous append/expiry/restart and collision in published/reserved v8 cursor tokens; out-of-scope lookups cannot widen. Prove displaced/discarded bundles last-reference release outside lock and timed-out workers cannot publish. Tests compile against task1 store interfaces and fail behaviorally against nonfunctional seams.
  - Blocked-by: tn4py0x (Define portfolio interfaces and deterministic captured-view fixture types), tn4py0z (GREEN: integrate T-63 read foundation into the risk harness and pass the gate)
  - Stream: 2
  - Requirements: [6.1](requirements.md#6.1), [6.3](requirements.md#6.3), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)
  - References: design.md

- [x] 7. GREEN: implement bounded reusable snapshot store and staged per-store publication <!-- id:tn4py13 -->
  - Implement Transit/Transit/MCP/MCPReusableSnapshotStore.swift to pass task6; immutable root/page/index bundles, complete captured values/options/metadata, pinning, reservations, lifecycle generation and monotonic expiry.
  - Keep separate eight/16MiB budget from ordinary pages (up to32MiB combined logical bytes plus heap overhead). Prepare combined selected changes per store outside domain; validate all candidates before nonthrowing one-swap/store commit; preencoded failures replace success.
  - Use sole T-63 MCPReadPublicationDomain lock, bounded bookkeeping, no nested independent commit lock. Carry retirement bundles through unlock before ARC release on success/rejection/timeout/purge/teardown; retained work remains charged by T-63 until physical completion.
  - Expose retained-view source and store lifecycle hooks for T-63 registration, without editing shared initialization/server files.
  - Blocked-by: tn4py12 (RED: add reusable retention and aggregate publication race tests)
  - Stream: 2
  - Requirements: [6.1](requirements.md#6.1), [6.3](requirements.md#6.3), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)
  - References: design.md

- [x] 8. RED: add snapshot task projection and reconciliation tests <!-- id:tn4py14 -->
  - Add Transit/TransitTests/MCPPortfolioProjectionTests.swift: summary/full captured description/metadata, omitted comment bodies but original comment-covered r1, effective status/storedStatus, supported project/status filters, duplicate status dedup and empty-array semantics.
  - Assert summary status buckets equal filtered task counts across all pages after live mutation/deletion/import; original window/asOf/freshness/expiry never change. Declared scoped keys constrain closure endpoints; incompatible options, selectedQuery capture or outside scope fail without live recapture.
  - Test stable task UUID/physical ordering, summary normalized-name/UUID/physical and milestone ordering; v8 continuation routing remains distinct from expired ordinary v4 cursors.
  - Blocked-by: tn4py11 (GREEN: implement dedicated summary service and completion-window parser), tn4py13 (GREEN: implement bounded reusable snapshot store and staged per-store publication)
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7)
  - References: design.md

- [x] 9. GREEN: implement captured task projection and strict snapshot query parser <!-- id:tn4py15 -->
  - Implement Transit/Transit/MCP/MCPPortfolioProjection.swift and MCPSnapshotTaskQueryRequest.swift to pass task8; consume immutable retained capture only and preserve canonical revisions before derived output transformations.
  - Require snapshotId/detailLevel/includeComments:false/limit1–100, optional projectId/status array; reject unsupported fields/filter/scope/policy overrides. Project names are not accepted in snapshot task mode.
  - Return new pages sharing original metadata, typed scope and deadline through staged append reservations; no lifetime extension or live model/comment fetch.
  - Blocked-by: tn4py14 (RED: add snapshot task projection and reconciliation tests)
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7)
  - References: design.md

- [x] 10. Define registry descriptor and integrate shared dispatch wiring through T-63 <!-- id:tn4py16 -->
  - Types/schema/wiring exemption: implement Transit/Transit/MCP/MCPPortfolioToolDefinitions.swift descriptor. Encode strict initial/replay/continuation branches, readPolicy default, count/window/activity/diagnostic/freshness/expiry/failure semantics and single-object POST transport restriction in tool descriptions/schema strings.
  - Explicitly document legacyactiveTaskCount nonterminal meaning, ordinary stored-status vs snapshot effective-status filtering, current-record rather than historical completion counts, timestamps and excluded arbitrary edits. No standalone documentation task in this code list.
  - T-63 alone wires descriptor, dependencies, readOnlyToolNames/fallback storage classification, dispatch before ordinary parser, retained-view source and lifecycle invalidation in shared files. Ordinary task text/schema behavior remains compatible; schema permits deliberate snapshot mode only.
  - Use schema/route assertions in subsequent handler test pair; compile integration in coordinated Xcode27 slot. Do not add App Intents/report UI/schema migrations.
  - Second handoff: parent gives T-63 the T-2382 module revision and agreed entrypoint signatures; T-63 supplies its registration/lifecycle integration revision. This is later than the foundation handoff and does not retroactively block task3.
  - Blocked-by: tn4py11 (GREEN: implement dedicated summary service and completion-window parser), tn4py13 (GREEN: implement bounded reusable snapshot store and staged per-store publication), tn4py15 (GREEN: implement captured task projection and strict snapshot query parser)
  - Stream: 1
  - Requirements: [2.3](requirements.md#2.3), [2.5](requirements.md#2.5), [3.4](requirements.md#3.4), [4.2](requirements.md#4.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.6](requirements.md#6.6), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: design.md

- [x] 11. RED: add portfolio handler wire, validation and error tests <!-- id:tn4py17 -->
  - Add Transit/TransitTests/MCPPortfolioHandlerTests.swift against tool-call dispatch: strict wrong/missing/unknown types, exclusive selectors, normalized-name ambiguity, window precision, limit, initial vs snapshotId-only replay vs cursor branches and policy precedence.
  - Verify _meta[me.nore.ig.transit/read] frozen capture identity/asOf/freshness/read for populated/empty/replay/continuation; required read/coherence/serialization failure distinguished from zero results and no metadata invented before capture.
  - Assert advertised schema/description semantics and fallback classification; existing query_tasks ordinary raw status/order/fields/v4 frozen metadata and get_projects.activeTaskCount remain unchanged. New handlers initially fail.
  - Blocked-by: tn4py16 (Define registry descriptor and integrate shared dispatch wiring through T-63)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.3](requirements.md#2.3), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.4](requirements.md#3.4), [4.2](requirements.md#4.2), [6.1](requirements.md#6.1), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: design.md

- [x] 12. GREEN: implement isolated portfolio and snapshot task handlers <!-- id:tn4py18 -->
  - Implement Transit/Transit/MCP/MCPToolHandler+PortfolioSummary.swift and +SnapshotTaskQuery.swift to pass task11, orchestrating T-63 admitted capture, pure aggregation/projection, private encoding and staged store publication.
  - Scalar validate before capture; resolve selectors within provider fence; require complete declared-scope evidence/full canonical r1/comment evidence. Replay/continuation never refetch or refresh and return original encoded values/metadata.
  - Return PreparedReadResult bytes + staged publication to enclosing individual permit; generic internal aggregate publication remains supported. Never publish IDs before complete encoding/gate success; expose typed validation/identity/compatibility/read/capacity errors with T-63 timeout/busy semantics.
  - Blocked-by: tn4py17 (RED: add portfolio handler wire, validation and error tests)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.3](requirements.md#2.3), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.4](requirements.md#3.4), [4.2](requirements.md#4.2), [6.1](requirements.md#6.1), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: design.md

- [x] 13. RED: add integrated publication, reconciliation and lifecycle regressions <!-- id:tn4py19 -->
  - Add Transit/TransitTests/MCPPortfolioIntegrationTests.swift exercising actual Hummingbird/router/store integration for individual POSTs: reconciliation, saved-only capture, expiry/lifecycle, bounded reads, deadline/encoding/publication failure and no unreachable IDs. Preserve two selected same-store changes, multi-store rejection, ready/blocked children and aggregate encoding/cutoff coverage at the internal coordinator boundary; do not introduce production JSON-RPC arrays.
  - Cover actual saved-only context/import fence, post-capture edits and full r1/body omission, five-minute expiry/restart/late-worker racing append, eight unfinished reads/ninth busy and unchanged application-level mutate_tasks receipt handling.
  - Repeat generated reconciliation and 2,375-task/comment fixtures at app boundary, assert transport availability <=5s without claiming hard real-time OS guarantees. Reserve parent-coordinated Xcode27 slot; no shared build concurrency.
  - Final cross-ticket acceptance requires both T-2382 modules and T-63 remaining covered-read conversions/registration on parent-approved combined revision. This final acceptance is separate from task3 foundation proof; parent schedules one integrated heavy test slot.
  - Blocked-by: tn4py18 (GREEN: implement isolated portfolio and snapshot task handlers)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: design.md

- [x] 14. GREEN: fix integrated portfolio path to pass end-to-end regression suite <!-- id:tn4py1a -->
  - Correct only T-2382 service/store/parser/projection/handler files revealed by task13; T-63 owns common coordinator/capture/schema/server fixes through parent. Re-run changed targeted tests in the same coordinated slot.
  - Reject any fix that saves unrelated UI work, broadens scope, changes ordinary pagination, releases lingering admission early, publishes before final enclosing response encoding or relaxes response limit. Material approved-contract change returns to parent approval gate.
  - Keep all modules reachable via common registry/dispatch/lifecycle; remove temporary interface scaffolding and ensure no orphan code. Verify requirement matrix before completing integration.
  - Blocked-by: tn4py19 (RED: add integrated publication, reconciliation and lifecycle regressions)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: design.md

- [x] 15. Run required code checks and serialized Xcode27 regression tests <!-- id:tn4py1b -->
  - Run make lint and repository validation guards, then make test-quick and required macOS/iOS build/test coverage appropriate to shared MCP changes in parent-coordinated Xcode27 slots; no simultaneous heavy Xcode/simulator runs with T-63/other worker.
  - If Makefile fails, inspect failure and use Xcode MCP when available; no downgrade. Record exact unavailable MCP/build/permission blocker rather than claiming a pass. Re-run only after changed code/new evidence.
  - This is a testing-only task: fix findings through paired owning tasks and re-run affected tests; preserve T-2380 write/read guard regression coverage. Full pre-push-review plus Pulsar follows as separate authorized workflow, with publication permission resolved through parent before any unauthorized external publish.
  - Blocked-by: tn4py1a (GREEN: fix integrated portfolio path to pass end-to-end regression suite)
  - Stream: 1
  - Requirements: [2.3](requirements.md#2.3), [2.5](requirements.md#2.5), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.5](requirements.md#6.5), [7.1](requirements.md#7.1), [7.3](requirements.md#7.3), [7.5](requirements.md#7.5)
  - References: design.md
