---
references:
    - specs/structured-mcp-results/requirements.md
    - specs/structured-mcp-results/design.md
    - specs/structured-mcp-results/decision_log.md
metadata:
    approval: pending
    ticket: T-2383
---
# Structured MCP results — implementation tasks

- [ ] 1. Define immutable result and modern protocol boundary interfaces <!-- id:gpzncvl -->
  - Interface-only exemption: declare macOS-gated nonisolated Sendable MCPResultSource/context/presentation/recovery, lossless document and protocol request/availability input types under Transit/Transit/MCP/Results and MCP/Protocol; no runtime implementation or T63-owned common edits.
  - Fix callable source/presentation/complete-response/fallback descriptor signatures against approved design; nil/false/true error presence stays explicit. Support protected, synthetic application-batch and unprotected-maintenance recovery without new keys.
  - One stream owns result/shared integration; stream2 may implement isolated protocol modules after these interfaces. No task is claimed or executed until owner task approval; every build/test also waits for T63 slot release.
  - Provide compiler-valid protocol requirements/value constructors and minimal throwing placeholders where signatures require bodies; RED fixtures must execute and fail expected behavior rather than treating missing declarations/compiler errors as RED evidence.
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4), [3.4](requirements.md#3.4), [5.2](requirements.md#5.2), [6.1](requirements.md#6.1)
  - References: design.md, decision_log.md

- [ ] 2. RED: specify lossless source parsing and generated-versus-retained failure properties <!-- id:gpzncvm -->
  - Add MCPJSONDocumentTests and MCPResultSourceTests under Transit/TransitTests with Swift Testing; seeded nested UTF8/escape/decimal/exponent/large-integer/Boolean/missing-null generation plus shrinking; reject duplicate keys, invalid UTF8/escapes, trailing tokens and malformed numbers.
  - Assert original text and validated payload tokens remain exact. Malformed generated JSON must throw; malformed retained JSON preserves raw text/isError as unreadable/unestablished; plain errors remain declared text. Tests initially fail against declaration-only implementation, then run unchanged in task3.
  - Blocked-by: gpzncvl (Define immutable result and modern protocol boundary interfaces)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [2.4](requirements.md#2.4), [3.3](requirements.md#3.3)
  - References: design.md, Transit/Transit/MCP/Results/MCPJSONDocument.swift, Transit/Transit/MCP/Results/MCPResultSource.swift

- [ ] 3. GREEN: implement owned lossless JSON documents and source factories <!-- id:gpzncvn -->
  - Implement MCPJSONDocument.swift iterative parser and MCPResultSource.swift factories; preserve validated original fragment, member positions, unknown fields and number lexemes without Double/Any reconstruction.
  - Honor injected cancellation/deadline checks and retain private immutable backing; do not alter MCPCanonicalJSON or receipt validation. Make task2 examples/properties pass with no model/context access.
  - Blocked-by: gpzncvm (RED: specify lossless source parsing and generated-versus-retained failure properties)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [2.4](requirements.md#2.4), [3.3](requirements.md#3.3)
  - References: design.md, Transit/Transit/MCP/Results/MCPJSONDocument.swift, Transit/Transit/MCP/Writes/MCPCanonicalJSON.swift

- [ ] 4. RED: specify deterministic link, category and recovery presentation <!-- id:gpzncvo -->
  - Add MCPResultPresentationTests: documented task/project source positions, relationship pointers, conflicting display IDs, invalid UUIDs, unknown nested id fields, and deterministic repeat presentation after unrelated model changes.
  - Table-test all approved error categories, explicit provider phases, unclassified historic codes, unsupported/contradictory evidence, accepted/outcome/retryAction preservation and uncertainty precedence. Supplemental fields never overwrite colliding source names; no URI/navigation scheme.
  - Reuse task2 seeded source generator for deterministic presentation/collision properties, not only fixed examples; shrink unknown fields/positions while preserving the asserted identity/recovery invariant.
  - Blocked-by: gpzncvn (GREEN: implement owned lossless JSON documents and source factories)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.5](requirements.md#3.5), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)
  - References: design.md, Transit/Transit/MCP/Results/MCPResultAdapter.swift

- [ ] 5. GREEN: implement source-only presentation and typed provider selectors <!-- id:gpzncvp -->
  - Implement MCPResultAdapter.swift selector tables and typed additional provider positions, validate each UUID against immutable source, preserve array ordering and deterministic pointer/type/UUID ordering.
  - Produce explicit unavailable links and supplement-only categories/recovery. Known receipt codes use validated provider evidence; no localized message matching, live reread, receipt rewrite, fresh-key escape from uncertainty or revision minting. Pass task4.
  - Blocked-by: gpzncvo (RED: specify deterministic link, category and recovery presentation)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.5](requirements.md#3.5), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)
  - References: design.md, Transit/Transit/MCP/Results/MCPResultAdapter.swift

- [ ] 6. RED: specify complete response encoding and preeffect fallback selection <!-- id:gpzncvq -->
  - Add MCPResultEncoderTests for complete modern/text/structured/_meta/RPC bytes, valid request-ID correlation, exact optional isError, source fragments and safe surrounding JSON escaping.
  - Use synthetic protected/batch/maintenance sources to prove fallback bytes are fully deliverable before effects, failed preparation invokes zero effects, and later selection never calls any failed source/presentation/envelope encoder again. Batch fixture uses summary serialization_failed/effect evidence unestablished and original indexes/tool/key/UUID; no production mutate_tasks dependency.
  - Reuse task2 seeded source values to property-check full encoding: exact source/text presence and numbers survive wrapping, malicious surrounding strings cannot escape fields, metadata remains outside source; fixed transaction/fallback fault tests stay separate.
  - Blocked-by: gpzncvp (GREEN: implement source-only presentation and typed provider selectors)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [5.4](requirements.md#5.4)
  - References: design.md, Transit/Transit/MCP/Results/MCPResultEncoder.swift

- [ ] 7. GREEN: implement complete result bytes and provider-owned mutation fallbacks <!-- id:gpzncvr -->
  - Implement MCPResultEncoder.swift validated fragment writer and complete immutable fallback preparation accepting provider-owned logical source/context/metadata. Retained tool fragments omit RPC ID; encode fresh outer IDs only.
  - Keep preencoded response selection separate from encoding; maintenance reconciliation carries no invented key, protected recovery preserves original tool/key, batch payload remains untouched. Pass task6; this new-file API is deliverable to T2384 without waiting for production batch wiring.
  - Blocked-by: gpzncvq (RED: specify complete response encoding and preeffect fallback selection)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [5.4](requirements.md#5.4)
  - References: design.md, Transit/Transit/MCP/Results/MCPResultEncoder.swift

- [ ] 8. RED: validate structured output schemas across every source variant <!-- id:gpzncvs -->
  - Add MCPResultSchemaTests exporting actual generated descriptors/result fixtures to a test-owned temporary directory, plus tests/validation/validate_mcp_result_schemas.py host runner; app test processes do not read the host checkout.
  - Use a standards-compliant Draft202012 validator for schemas and instance fixtures: arrays/scalars/null, JSON/text/unreadable, success/errors, historical unknown names/types, missing/null/false, synthetic batch originals. Reject malformed wrapper/presentation and unreadable-with-payload variants; no network refs. Schema-tool prerequisite must be met before validation is claimed.
  - Blocked-by: gpzncvr (GREEN: implement complete result bytes and provider-owned mutation fallbacks)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [3.2](requirements.md#3.2)
  - References: design.md, Transit/Transit/MCP/Results/MCPResultSchemas.swift, tests/validation/validate_mcp_result_schemas.py

- [ ] 9. GREEN: implement output descriptor/schema providers and host fixture validation <!-- id:gpzncvt -->
  - Implement MCPResultSchemas.swift explicit2020-12 self-contained wrapper definitions; source JSON accepts any original JSON value/unknown fields, while source-kind and presentation invariants remain constrained.
  - Connect schema descriptors to the synthetic provider seam and test runner/export path; no independent edits to shared MCPTypes or common registry. Keep existing input-schema support unchanged until coordinated integration. Pass task8.
  - Blocked-by: gpzncvs (RED: validate structured output schemas across every source variant)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [3.2](requirements.md#3.2)
  - References: design.md, Transit/Transit/MCP/Results/MCPResultSchemas.swift, tests/validation/validate_mcp_result_schemas.py

- [ ] 10. RED: bound expanded result preparation with production-shaped synthetic cases <!-- id:gpzncvu -->
  - Add MCPResultPreparationBudgetTests with 2000 synthetic records/multiple pages and seeded large text/number fields; blocked parser/encoder and fake cancellation/cutoff inputs assert timely complete failure, never partial success.
  - Test exact backing charges for raw text, structured fragments and original metadata, shared backing once, pending reservations and both ordinary/reusable16-MiB boundary fixtures. Over-limit results must fail capacity/deadline, not be truncated or gain larger limits. This is automated code verification of the design measurement risk, not a standalone metrics exercise.
  - Blocked-by: gpzncvt (GREEN: implement output descriptor/schema providers and host fixture validation)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [2.2](requirements.md#2.2), [3.3](requirements.md#3.3), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)
  - References: design.md, Transit/TransitTests/MCPResultPreparationBudgetTests.swift

- [ ] 11. GREEN: implement charged frozen result preparation and cancellation checks <!-- id:gpzncvv -->
  - Implement value-only frozen-fragment/size preparation in Results modules using task1 seams. Avoid needless duplicate backing, preserve all existing capture/index charges and metadata; check supplied cutoff/cancellation between bounded encoding stages.
  - Pass task10 before integrating retention or common transport. If volume preparation cannot succeed inside limits, select the already prepared defined failure and discard privately staged output; no deadline/capacity expansion or weakened evidence.
  - Blocked-by: gpzncvu (RED: bound expanded result preparation with production-shaped synthetic cases)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [2.2](requirements.md#2.2), [3.3](requirements.md#3.3), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)
  - References: design.md, Transit/Transit/MCP/Results/MCPResultEncoder.swift

- [ ] 12. RED: specify modern request validation and stateless discovery <!-- id:gpzncvw -->
  - Add MCPModernValidatorTests/DiscoveryTests with pure immutable availability inputs: metadata/header/code/status matrix, Base64 name sentinel/UTF8, conflicting headers, modern-only versions and data.supported, readable versus omitted error IDs, arrays/null IDs/unknown methods and notification-shaped tools/call zero dispatch.
  - Test complete discovery/tool-list result, zero/public cache metadata, stable name order and optional capability validation without prior-request state. These new-file fixtures use synthetic definitions; no T63 common/router edits before handoff.
  - Blocked-by: gpzncvl (Define immutable result and modern protocol boundary interfaces)
  - Stream: 2
  - Requirements: [3.2](requirements.md#3.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.6](requirements.md#5.6)
  - References: design.md, Transit/Transit/MCP/Protocol/MCPModernValidator.swift, Transit/Transit/MCP/Protocol/MCPModernDiscovery.swift

- [ ] 13. GREEN: implement pure modern-only validator and discovery values <!-- id:gpzncvx -->
  - Implement MCPModernRequest.swift/MCPModernValidator.swift/MCPModernDiscovery.swift from task12 fixtures; per-request metadata only, standard errors, request-only method classification, immutable availability.
  - Expose validated protocol classification to later router wiring; covered tool arguments remain unvalidated until admitted bounded worker. No session/initialize/GET stream/wire arrays, resource/prompt/sampling features or client settings. Pass task12.
  - Blocked-by: gpzncvw (RED: specify modern request validation and stateless discovery)
  - Stream: 2
  - Requirements: [3.2](requirements.md#3.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.6](requirements.md#5.6)
  - References: design.md, Transit/Transit/MCP/Protocol/MCPModernValidator.swift

- [ ] 14. RED: exercise shared provider, replay and effect-aware failure integration <!-- id:gpzncvy -->
  - External gate: T63 shared-file ownership handoff at recorded base commit and heavy-test slot release, including its provider regression fix. Do not edit shared tests/helpers/sources before coordinated ownership; isolated tasks above do not wait for production T2384.
  - Extend MCPToolHandler/WriteCoordinator/HTTP fixture suites and add result-provider integration fixtures: every enabled current tool/maintenance result, plain/JSON errors, historic replay after edits/deletion with new RPC ID/same key, no receipt/expiry changes, unsupported evidence.
  - Assert actual protected-path name/comment/description trim-clear/newline parity from saved snapshots at same covered r1; parent labels excluded. Dirty UI/captured saved evidence must not cause adapter model reads, saves or rollback. Batch-specific clean-phase safeguards stay in T2384.
  - Inject protected postcommit outer failure and maintenance inner encodeAsJSONString/final envelope/delivery faults separately; preparation failure prevents effects and selected fallback bytes preserve original-key or no-key reconciliation. Router tests prove origin/headers/notification rejection before effects, covered invalid arguments enter bounded admission, immutable availability avoids preadmission MainActor work.
  - Blocked-by: gpzncvv (GREEN: implement charged frozen result preparation and cancellation checks), gpzncvx (GREEN: implement pure modern-only validator and discovery values)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.6](requirements.md#5.6)
  - References: design.md, Transit/Transit/MCP/MCPToolHandler.swift, Transit/Transit/MCP/MCPTypes.swift, Transit/Transit/MCP/MCPServer.swift, Transit/Transit/MCP/Writes/MCPWriteCoordinator.swift

- [ ] 15. GREEN: integrate common source/schema/fallback and modern dispatch at handoff <!-- id:gpzncvz -->
  - Under T63 coordinated ownership, wire source origins/error phases in textResult/errorResult/protected outcomes/maintenance/persistence failures; install output-schema descriptors and resultType/structured/_meta support once in MCPTypes/definitions/handler.
  - Adapt terminal/replay output downstream without changing receipt JSON/format/r1/retention or service normalization. Route maintenance inner encoding failures to effect-aware ready-byte selection. Wire modern POST/header/Origin/format validation plus immutable availability classification ahead of read admission; remove legacy wire-array/init/session/GET pathways and update their tests.
  - Pass task14 and deliver a recorded common seam commit to T2384: source/JSON representation/schema descriptors/complete fallback/normal selection. T2384 owns its consumer/real mutate_tasks registration and safety policy; this task and T2383 final validation never block on production batch completion.
  - Blocked-by: gpzncvy (RED: exercise shared provider, replay and effect-aware failure integration)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.6](requirements.md#5.6)
  - References: design.md, Transit/Transit/MCP/MCPTypes.swift, Transit/Transit/MCP/MCPToolDefinitions.swift, Transit/Transit/MCP/MCPServer.swift, Transit/Transit/MCP/MCPServer+Responses.swift, Transit/Transit/MCP/MCPToolHandler.swift

- [ ] 16. RED: prove frozen retention and atomic modern publication under faults <!-- id:gpzncw0 -->
  - Extend ordinary and T2382 reusable snapshot test suites using T63 fake clocks/barriers and real owner store seams; frozen text/payload/presentation/meta/policy/expiry/r1 survive edits/import changes and freshRPCIDs without reread/reclassification.
  - Inject required comment/history/capture/parser faults, explicit selector absence, expanded capacity failure, cancellation while encoding/preparing/offering, expired/stale publication, listener stop/restart and blocked physical finalizers. Assert no unpublished IDs/partial records, no serialization under gate,8 unfinished physical slots survive restart.
  - Explicit includeComments:false full/reusable-page cases must retain the original canonical comment-covered r1, even after later comment changes; only bodies are omitted.
  - Blocked-by: gpzncvz (GREEN: integrate common source/schema/fallback and modern dispatch at handoff)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [3.3](requirements.md#3.3), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)
  - References: design.md, Transit/Transit/MCP/MCPTaskQuerySnapshotStore.swift, Transit/Transit/MCP/Reads, /Users/arjen/Documents/Codex/2026-10-03/task-2/transit/specs/portfolio-summaries/design.md

- [ ] 17. GREEN: wire frozen tool fragments and full-byte read publication <!-- id:gpzncw1 -->
  - Use T63 retainedPage/PreparedReadResult seam and shared publication domain; privately charge/reserve expanded frozen fragments and original metadata/policy/expiry, then offer complete modern/text/structured/_meta/RPC bytes and all prepared publications.
  - Continuation encodes only new RPC wrapper. Keep original five-sec cutoff, eight physical workers and separate five-minute/eight-snapshot/16-MiB ordinary/reusable limits; atomic selection/discard only, large destruction outside lock, physical permits released by finalizers. Coordinate T2382 store-owned patch without altering aggregation. Pass task16.
  - Blocked-by: gpzncw0 (RED: prove frozen retention and atomic modern publication under faults)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [3.3](requirements.md#3.3), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)
  - References: design.md, Transit/Transit/MCP/MCPToolHandler+TaskQuery.swift, Transit/Transit/MCP/Reads, Transit/Transit/MCP/MCPTaskQuerySnapshotStore.swift

- [ ] 18. RED: specify request-scoped subscription ordering and cleanup <!-- id:gpzncw2 -->
  - Replace legacy session/GET stream expectations in MCPToolListChangeNotificationTests/MCPServerRouteTests; valid POST subscriptions require request IDs/modern headers/SSE Accept and acknowledge only supported requested filters.
  - Stress immediate availability changes before/after acknowledgement, coalescing, parallel string/integer subscription IDs, disconnect/shutdown/restart/port-change cleanup and graceful complete closure. First acknowledgement is never evicted; no unrequested notification, session state or further canceled-stream delivery.
  - Blocked-by: gpzncw1 (GREEN: wire frozen tool fragments and full-byte read publication)
  - Stream: 1
  - Requirements: [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.1](requirements.md#6.1)
  - References: design.md, Transit/Transit/MCP/MCPToolListChangeBroadcaster.swift, Transit/Transit/MCP/MCPServer+ToolListNotifications.swift

- [ ] 19. GREEN: implement POST subscription broadcaster and lifecycle wiring <!-- id:gpzncw3 -->
  - Replace session-grouped broadcaster with request registrations, separate first-ack staging and bounded coalesced invalidations; carry original RPC subscription ID on every message and accepted filter only.
  - Integrate existing availability observer/service teardown/port-change hooks under handoff; flush SSE data frames, omit event IDs/resumability, graceful complete result on server closure where possible, cleanup exactly once. No store capture/read permit or extra progress stream. Pass task18.
  - Blocked-by: gpzncw2 (RED: specify request-scoped subscription ordering and cleanup)
  - Stream: 1
  - Requirements: [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.1](requirements.md#6.1)
  - References: design.md, Transit/Transit/MCP/MCPToolListChangeBroadcaster.swift, Transit/Transit/MCP/MCPServer+ToolListNotifications.swift, Transit/Transit/MCP/MCPServer.swift

- [ ] 20. RED: specify isolated client-readiness fixture and negotiation evidence checks <!-- id:gpzncw4 -->
  - Add automated fixture/harness tests with synthetic data: modern discovery/list/call/structured consumption, conforming subscription filter/first-ack/correlation, wrong/legacy protocol negatives, and no real writes or production endpoint replacement.
  - Write negotiation-evidence checks that reject binary symbols/version-only/legacy success, missing intended surfaces and missing structured consumption. Require concrete actual intended Codex surfaces, Claude Code and Desktop discovery/list/call traces; subscription only for opted-in installed surfaces plus conforming fixture. Actual runtime connection/settings prerequisites remain separate from coding.
  - Blocked-by: gpzncw3 (GREEN: implement POST subscription broadcaster and lifecycle wiring)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [3.2](requirements.md#3.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [6.3](requirements.md#6.3)
  - References: design.md, scripts/mcp-modern-readiness, prerequisites.md

- [ ] 21. GREEN: implement isolated loopback fixture and readiness trace verifier <!-- id:gpzncw5 -->
  - Implement scripts/mcp-modern-readiness test launcher/verifier using approved app encoder/validator test hooks on a separate loopback port and synthetic read-only records. Verify headers/meta/discovery/list/call/structured response and subscription evidence; verify fixture cannot address real store or replace production listener.
  - Pass task20. Produce machine-checkable evidence for each approved installed-client probe without installing clients, changing flags/connectors/settings, starting external-model agents or activating Transit. Unsupported modern runtime is an explicit blocker, not a fallback to legacy.
  - Blocked-by: gpzncw4 (RED: specify isolated client-readiness fixture and negotiation evidence checks)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [3.2](requirements.md#3.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [6.3](requirements.md#6.3)
  - References: design.md, scripts/mcp-modern-readiness, prerequisites.md

- [ ] 22. Test integrated modern contracts and approved client evidence <!-- id:gpzncw6 -->
  - Test-only task after T63 slot release: run selected Swift Testing suites and schema fixture validation then repository make lint/test-quick appropriate to changes, with owning TestModelContainer fixtures and no host-checkout reads in app test processes. Broaden only for new failures/unresolved concerns.
  - Validate approved real-client negotiation evidence with task21 harness only once prerequisites are satisfied; missing evidence keeps6.3 open. Exercise all present provider registrations and synthetic future batch seam; production T2384 completion is not a blocker or claimed proof.
  - No activation/settings/push/merge/deploy here. If prerequisites remain unavailable, report readiness blocked while retaining delivered common API; no false complete task status.
  - Blocked-by: gpzncw5 (GREEN: implement isolated loopback fixture and readiness trace verifier)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3)
  - References: design.md, requirements.md, prerequisites.md, Makefile
