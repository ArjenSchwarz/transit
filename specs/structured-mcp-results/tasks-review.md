# Structured MCP results: task review

Status: Rune plan b58298a approved at Sentinel_ba4c6123288881918042d6aeb8ba6dc5; design approval recorded at Sentinel_717be95229c48191a7c41b6e5e467e4c. No implementation or task execution. Internal critic and two independent internal peers complete; no remaining task-plan blockers.

## Rune validation

Actual installed Rune created the list and applied44 atomic add/update operations. `rune list` renders22pending tasks, explicit streams/dependencies and no parser warnings. `rune streams --json` confirms stream1 for Results/shared integration and stream2 for isolated Protocol modules, both dependent on interface1. Task1 is the only internally ready item, still gated by owner task approval. Ten GREEN tasks immediately follow their RED partners; task1 is interface-only and22 test-only.

A lightweight checker read Rune JSON and Markdown stable-ID mappings: all27 acceptance anchors referenced;22pending/none claimed; ten adjacent RED/GREEN edges; every dependency resolves; DAG acyclic. No application lint/build/test ran. Intentional requirements double-space Markdown is excluded only by per-command whitespace checking, without config edits.

## Traceability

| Acceptance criteria | Tasks / proof |
| --- | --- |
| 1.1–1.2 | 2–7 source/encoder token preservation;14–15 every provider and saved normalization parity. |
| 1.3 | 8–9 actual descriptor export/2020-12 instance validation;14–15 published schemas;20–22 consumer evidence. |
| 1.4 | 2–9 raw text and collision-free source/presentation;14–15 historic output. |
| 2.1 | 4–9 validated source preservation;14–15 historic replay after edits/deletion without expiry/store rewrite. |
| 2.2–2.3 | 10–11 charged preparation;16–17 frozen ordinary/reusable pages, metadata and comment-covered r1. |
| 2.4 | 2–9 unsupported/malformed/contradictory evidence;14–15 reconcile and no fabricated replay. |
| 2.5 | 14–15 protected retry newRPCID/same original tool/key/arguments. |
| 3.1–3.2,3.5 | 4–9 source-only categories/recovery and documented schema/descriptor contract;12–15 protocol errors remain separate. |
| 3.3 | 2–3 generated parse failure;10–11/16–17 complete read failure/no publication versus explicit selector absence. |
| 3.4 | 6–7 ready-byte fallbacks before effects;14–15 protected postcommit, maintenance inner/final/delivery faults; T2384 synthetic seam, not batch execution. |
| 4.1 | 14–15 actual path-specific name/comment/description trim-clear/newlines at same-covered-r1; no new normalizer. |
| 4.2–4.4 | 4–5 source-position/UUID unavailable links;14–15 replay remains deterministic; no T572 navigation. |
| 5.1–5.4 | 12–15 stateless discovery/headers/modern dispatch/result/cache/schema;18–19 legacy-listener replacement;20–22 consumption. |
| 5.5 | 18–21 first acknowledgement/filter/correlation/coalescing/disconnect/teardown. |
| 5.6 | 12–15/18–19 loopback Origin/Host/format rejection before effects/capture. |
| 6.1–6.2 | 10–11 design volume risk;14–17 admission/invalid arguments/atomic full-byte publication/physical finalizers/expanded charges;18–19 stream cancellation. |
| 6.3 | 20–22 isolated fixture/verifier, actual intended installed-client evidence prerequisites; no settings/activation implied. |

## Integration order and external gates

Deliver new-file source/presentation/encoder/schema units3(gpzncvn),5(gpzncvp),7(gpzncvr),9(gpzncvt), then common integrated seam15(gpzncvz) after T63's recorded ownership handoff/provider regression fix. T2384's real consumer/registration waits for that **delivered commit/interface**, rather than design approval alone. T2383 final22 uses synthetic batch source/fallback and present provider registrations, with no dependency on production batch completion. T2384 confirmed it records this forward edge and no reverse edge.

Read integration16–17 remains T63/T2383/T2382-owned and never supplies a batch read deadline/publication. Pure Protocol12–13 can run independently of Results after interfaces1, but common wiring is serial. Parent controls shared ownership and heavy slot; all builds/tests wait for release. Dirty-context batch guards/fresh preview remain T2384-owned; T2383 tests adapter purity/saved source consumption without duplicating recovery or changing standalone acceptance semantics.

## Prerequisites and boundaries

`prerequisites.md` records schema-validator availability, shared-owner/test-slot release and actual client connection/modern-runtime changes requiring exact authorisation. Host Python lacks jsonschema; no package was installed. Installed modern client code remains insufficient evidence. Client prerequisites block readiness completion22/6.3, not common seam15 delivery. No circular cross-ticket dependency or external fake Rune task IDs were created.

The only design measurement risk maps to automated volume/budget RED10/GREEN11 before integration14–21. Limit failure remains deadline/capacity/no publication, not truncated success. Property-generation tasks2/4/6 define lossless/deterministic invariants; transaction/publication fixtures14/16 test failures that property roundtrips cannot establish. Every new subsystem reaches common wiring, with no orphaned provider/test harness.

## Supporting documentation completion gate

Documentation remains outside the coding-only Rune list. The T2383 implementation owner tracks these approved-design deliverables separately; common API15 delivery does not wait for final prose, but feature completion/final22 sign-off does:

- [x] Owner: T2383 implementation owner. After integrated seam15, create `docs/mcp-result-contract.md` from the approved design and delivered schema/fixtures: wrapper version/source/text/error presence, historic replay and frozen cursors, error/retry/reconciliation rules, path-specific saved normalization, UUID-associated unavailable links, latest-only lifecycle and client readiness. Completion evidence is the exact committed document matched to current descriptor/examples.
- [x] Owner: T2383 implementation owner. Correct obsolete initialization/session/GET/wire-array statements and examples in `docs/mcp-write-contract.md` and affected repository MCP documentation after modern wiring15–19; preserve application key/receipt/r1 semantics and distinguish the T2384 application batch. Completion evidence is the recorded documentation commit and a read-through against the final wire/receipt fixtures.

These are required deliverables for AC1.3/3.5/4.1 and the approved parity audit, not added production scope or main-list noncoding tasks. If missing, report feature completion blocked even if coding checks pass. T2384 owns its additional batch-specific caller documentation.

## Critic

No coding-sequence blocker: RED/GREEN ordering, parallel pure protocol stream, early capacity risk and forward batch seam accepted. Adopted completion-tracking finding: caller docs cannot be satisfied by schema fixtures alone; explicit T2383 owner/deliverables/commit evidence and feature-completion gate now appear above without adding documentation creation to Rune tasks.

## Task approval gate

Route through parent after required reviews and phone delivery: **Do the tasks look good?** The actual starwave-tasks skill requires explicit approval and limits this phase to planning artifacts; no task approval has yet been received. Implementation remains a separate authorised workflow. No settings, endpoint activation, push/merge/deployment or heavy test execution occurs here.

## Independent peer review and final disposition

Mode: internal critic followed by two independent internal subagent perspectives under the documented fallback; no external model service received repository/spec content. Correctness peer accepted source/replay/property/fault coverage, forward15 delivery and separate16–17 atomic reads. API/maintainability peer accepted independent protocol stream, no reverse batch edge, tooling/client gates and separate documentation completion tracking. Both validated the critic's adopted documentation finding.

Minor API clarification adopted in interface1: provide compiler-valid protocols/value constructors/minimal throwing placeholders so RED fixtures execute behavioral failures, not merely missing Swift declarations. Task count, streams, stable IDs and dependencies remain unchanged. No review divergence or unresolved task-plan blocker remains. Future implementation measurements and actual client readiness remain explicit gates rather than assumed successes.

## Implementation authorisation and ownership

Parent verified owner “Approved” at Sentinel_ba4c6123288881918042d6aeb8ba6dc5 in direct response to task-plan/implementation question. Proceed independent modules/interfaces; T63 common-file handoff and T2382 current heavy-test slot remain external gates. T2384 now owns MCPWriteCoordinator.swift/coordinator-specific tests until coordinated integration. No client configuration/activation or merge/deploy permission is added. Test-only schema tooling needs task/tool-policy authorisation in isolated environment; request routed through parent.

## Pre-push documentation completion

The versioned result contract and legacy caller-document corrections are supplied following source review fix9c41be6. Internal documentation re-review checked actual schema, classifier, normalization authority, protocol headers/statuses, frozen capture and listener/physical-worker distinctions. Both JSON examples parse. AC6.3 remains unverified and is owner-approved deferred post-merge (Sentinel_c0dbfe3212888191bc01744c855f67bb), not a compatibility pass. The exact documentation commit is recorded in the pre-push handoff.
