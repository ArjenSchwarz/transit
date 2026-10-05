---
references:
    - specs/typed-task-links/requirements.md
    - specs/typed-task-links/design.md
    - specs/typed-task-links/decision_log.md
metadata:
    amendment_review: approved-a64e595-Sentinel_08cb318218788191a85da25d1206979f
    approval: approved-18a268f-Sentinel_d1ba9360969c81918777711b2420bfc7
    deferred_ticket: T-2402-Set-up-isolated-CloudKit-integration-testing
    scope: participating-write-coordination-and-owned-save
    scope_amendment: Sentinel_c95239aefa6481919303c2353b8a9e9c-participating-writes
---
# Typed task links implementation tasks

- [x] 1. Red: test pre-feature store migration and schema parity <!-- id:ev1ktkw -->
  - Create serialized Swift Testing disk fixtures in TransitTests/TaskLinkMigrationTests.swift using an owning TestModelContainer and a reproducible pre-feature schema; assert unchanged task/comment fields and retained receipt bytes after reopen, empty graph incidence and both new model registrations.
  - Test defaulted/optional CloudKit-compatible scalar schema, no unique/cascade attributes, UUID physical multiplicity and every app/probe/container schema listed by the design audit. Use copied or synthetic test stores only.
  - Retain the prepared optional development CloudKit schema/deletion smoke source outside default targets; its compilation, isolated environment setup and live execution are deferred to the separate owner-requested ticket. Do not claim its assertions executed or remote convergence.
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.6](requirements.md#5.6), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [x] 2. Green: implement pre-feature store migration and schema parity <!-- id:ev1ktkx -->
  - Add Models/TaskLinkOccurrence.swift and TaskLinkRemovalEvidence.swift with immutable scalar identities/endpoints/kind and separate evidence; wire TransitApp, TestModelContainer and relevant tests/mcp-write-probe schemas.
  - Adapt exact types/imports against the explicit latest verified compatible merged foundation base. Re-audit every schema/snapshot consumer; preserve unrelated task history and production store. If additive disk migration fails, stop dependent work and return the design for review.
  - Complete the in-scope local gate with actual eight-entity closed-store upgrade/final reopen, preserved original fields/receipt bytes/physical multiplicity, empty graph tables, executed scalar/default/optionality/no-unique/no-relationship metadata assertions and all current factory registrations/manual legacy-mode review. Live Development setup/schema/export/deletion verification is explicitly deferred by the owner amendment, not marked passed. No production promotion/records/settings reset. Owned task/link/removal/terminal-receipt saving and participating-write coordination remain required.
  - Blocked-by: ev1ktkw (Red: test pre-feature store migration and schema parity)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.6](requirements.md#5.6), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [x] 3. Red: test coordinated saved validation and owned receipt commitment <!-- id:ev1ktky -->
  - Write disk-backed controls for participating coordinator writes, immediate fresh saved validation, stale registered source/endpoint observations, changed preconditions/cycles before apply, and all-or-none owned domain/graph/receipt save/encoding failures. Preserve existing read-first and internal-save-abort counterexamples as documented-limit evidence; they are not all-writer completion gates.
  - Require all-or-none originating task/edge/removal-evidence/terminal-receipt outcomes in independently reopened saved state; test dirty contexts before acceptance and after await success/error, retained replay without repair/save and uncertain recovery. Recast opt-in outside-writer endpoint/cycle races as allowed-race observations of saved faults, not rejection/no-domain-effect expectations; actual projection diagnostics are exercised by tasks5/6 and integrated tests21/22 after those components exist. Test that participating operations cannot interleave the synchronous final phase; do not claim sync/import exclusion.
  - Blocked-by: ev1ktkx (Green: implement pre-feature store migration and schema parity)
  - Stream: 1
  - Requirements: [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [5.5](requirements.md#5.5), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [x] 4. Green: implement coordinated saved validation and owned receipt commitment <!-- id:ev1ktkz -->
  - Implement the minimum shared coordinator policy/adapter for the participating synchronous MainActor saved-validation/apply/stage/save phase, with clean checks around preparation and explicit fresh saved resolution. Reuse the T-2384 policy and T-2380 receipt engine; retain one same-store domain/result commitment and existing replay/recovery semantics.
  - Complete the amended coordination, fresh-validation and owned-save tests before dependent graph-write integration. Outside writers/imports may race and produce temporary inconsistent links; projection reports their available evidence without automatic repair or post-commit rollback. No persistence-redesign or all-independent-writer predicate-fence proof is required. Ordinary implementation still stops on unsafe/ambiguous evidence, dirty drafts or uncertain persistence.
  - Blocked-by: ev1ktky (Red: test coordinated saved validation and owned receipt commitment)
  - Stream: 1
  - Requirements: [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [5.5](requirements.md#5.5), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [x] 5. Red: test normalized graph projection and exact change planning <!-- id:ev1ktl0 -->
  - Write TaskLinkGraphTests/TaskLinkPlanTests with seeded Swift Testing generated small graphs and an independent reference for inverse/reversed normalization, permutation invariance, SCC membership, direct blockers and duplicate paths.
  - Cover cross-project/missing/colliding identities, imported repeated occurrences, Done/Abandoned/unknown, valid Done ancestry exceptions, duplicate cardinality/chains/cycles/retarget and removal-only incremental repair. Seed outside-writer race faults into actual projection expectations for updated endpoint assessments and cycle/cardinality/identity/removal diagnostics, preserving the original committed receipt. Exact selector collisions fail closed; same-logical remove/add rejects; missing endpoint needs no invented revision.
  - Blocked-by: ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktkx (Green: implement pre-feature store migration and schema parity)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.2](requirements.md#4.2), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [8.1](requirements.md#8.1)
  - References: design.md, requirements.md, decision_log.md

- [x] 6. Green: implement normalized graph projection and exact change planning <!-- id:ev1ktl1 -->
  - Implement value-only TaskLinkGraph/TaskLinkPlan and Services/TaskLinkService normalization/indexing. Preserve all physical matches and malformed evidence; iterative SCC uses every structurally resolvable dependency row without dedup hiding cycle evidence.
  - Project with frozen removal evidence/evaluation instant; distinguish unblocked/blocked/invalid/unavailable. Validate complete proposed results, exact incidence/fingerprint removal and cardinality/cycles; no automatic canonical redirect, flattening, status changes or consolidation.
  - Blocked-by: ev1ktl0 (Red: test normalized graph projection and exact change planning), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.2](requirements.md#4.2), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [8.1](requirements.md#8.1)
  - References: design.md, requirements.md, decision_log.md

- [x] 7. Red: test bounded saved capture and graph-closure capacity <!-- id:ev1ktl2 -->
  - Add TaskLinkReadCaptureTests with pending insert/edit/delete in source/endpoint/occurrence/evidence/comments and independent saved contexts, failures/repeated identities and link-only history fence changes.
  - Write early scaling/deadline/retained-byte fixtures under unchanged five-second/eight unfinished-read and five-minute/eight-view/16-MiB limits. Cover cross-project closure not selected/countable, complete cycle evidence, timed-out lingering physical slots, frozen expiry instant and no late publication.
  - Blocked-by: ev1ktl1 (Green: implement normalized graph projection and exact change planning), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment)
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4), [5.4](requirements.md#5.4), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [x] 8. Green: implement bounded saved capture and graph-closure capacity <!-- id:ev1ktl3 -->
  - Extend T-63 CapturedReadView/ReadTask/MCPReadCaptureBuilder DTOs, fence and prepared capture path with occurrence/removal-evidence/endpoint closure. Use fresh autosave-disabled saved contexts and immutable Sendable values; no @Model return from child tasks.
  - Gate downstream capture/query work on passing bounded capacity fixtures. On excess return existing typed failure and optimize within budgets; no larger cap/partial unblocked result. Freeze graph/evaluation time and charge all retained evidence/index/result bytes; defer current task revision wiring to the next pair, never falsely mark absent evidence empty.
  - Blocked-by: ev1ktl2 (Red: test bounded saved capture and graph-closure capacity), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment)
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4), [5.4](requirements.md#5.4), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [x] 9. Red: test graph-covered current task revision and historic result compatibility <!-- id:ev1ktl4 -->
  - Add TaskLinkRevisionTests covering explicit empty incidence transition, incoming endpoint tokens, physical multiplicity/raw corrupt tuples, changed labels/status/evidence expiry exclusion and hidden link/comment bodies.
  - Exercise every MCPRecordSnapshot.task callsite: ordinary/full/reusable detail, create/update/status/add_comment and probes. Old tokens must conflict on fresh task status/property edits even no-link tasks; exact historic receipt replay stays byte-identical before current lookup.
  - Blocked-by: ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment)
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5), [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.2](requirements.md#6.2), [6.4](requirements.md#6.4), [6.6](requirements.md#6.6), [7.3](requirements.md#7.3), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [x] 10. Green: implement graph-covered current task revision and historic result compatibility <!-- id:ev1ktl5 -->
  - Require incidence coverage in MCPRecordSnapshot.task overloads; add linkContract and sorted incident tuples to canonical covered fields and revisionCoverage/graphCoverage to current task results while retaining r1 syntax.
  - Wire the completed saved capture and all write/result callsites to the authoritative builder. Preserve T-2383 historical raw fragments and explicit missing coverage; never remint old receipts/pages or fabricate graph coverage for legacy fixtures.
  - Blocked-by: ev1ktl4 (Red: test graph-covered current task revision and historic result compatibility), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5), [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.2](requirements.md#6.2), [6.4](requirements.md#6.4), [6.6](requirements.md#6.6), [7.3](requirements.md#7.3), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [x] 11. Red: test standalone wire deltas and accepted domain plan validation <!-- id:ev1ktl6 -->
  - Write TaskLinkWireTests for exact kebab-case types, UUID/l1/r1 shapes, 50 directives, create-additions-only, omitted fields, unique endpoint preconditions and inverses.
  - Separate pre-acceptance shape errors from saved-edge/semantic conflict validation after retained replay. Cover precise affected endpoints, source no-op guard, unknown/expired selector, retained no-op source incidence, physical UUID collisions, and duplicate retarget versus same-logical remove/add. Batch link fields reject before any item/key acceptance.
  - Add negative enablement tests: before protected task14 wiring succeeds, fresh link-bearing requests are unavailable rather than accepted/ignored. Assert schema descriptions cover directions, affected endpoint guards, no-op/repair/removal expiry, local-only guarantees and unsupported batches.
  - Blocked-by: ev1ktl5 (Green: implement graph-covered current task revision and historic result compatibility), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [3.2](requirements.md#3.2), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)
  - References: design.md, requirements.md, decision_log.md

- [x] 12. Green: implement standalone wire deltas and accepted domain plan validation <!-- id:ev1ktl7 -->
  - Add MCP/Links delta DTO/parser and l1 immutable occurrence fingerprint; extend standalone create/update validation and schemas, supplying TaskLinkPlan with complete captured result and endpoint guards.
  - Explicitly reject linkChanges/endpointPreconditions in T-2384 batch shapes. Keep existing field/permission semantics and all accepted domain failures in the original protected operation; no replacement set, alternate spelling, endpoint-first-match or implicit revision chaining.
  - Tool schema descriptions are executable caller guidance: explain type/direction, exact occurrence/preconditions, omitted versus empty evidence and unsupported batch fields; do not change public type spellings.
  - Keep fresh link-bearing writes unavailable behind the completed participating coordination and owned-save boundary/complete-apply enablement guard until task14 passes. Intermediate schemas must not accept and ignore directives; retained exact replay remains first.
  - Blocked-by: ev1ktl6 (Red: test standalone wire deltas and accepted domain plan validation), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [3.2](requirements.md#3.2), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)
  - References: design.md, requirements.md, decision_log.md

- [x] 13. Red: test protected standalone link create/update integration <!-- id:ev1ktl8 -->
  - Write TaskLinkWriteIntegrationTests for mixed task fields/links, allocation awaits, endpoint revision races, no-op exact replay, repair-only unrelated corruption, deleted targets, accepted rejection, delivery/save failure and restart uncertainty.
  - Verify task/occurrence deletion/addition/removal evidence/terminal result in one local save, original-key/tool/store binding and seven-day receipt behavior; dirty UI drafts remain untouched on all success/error/recovery paths. No global CloudKit atomicity claim.
  - Blocked-by: ev1ktl7 (Green: implement standalone wire deltas and accepted domain plan validation), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [1.3](requirements.md#1.3), [3.2](requirements.md#3.2), [3.5](requirements.md#3.5), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [7.3](requirements.md#7.3), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md

- [x] 14. Green: implement protected standalone link create/update integration <!-- id:ev1ktl9 -->
  - Wire MCPWriteCommand prepare/apply and MCPWriteCoordinator execution policy to the completed participating coordination and owned-save boundary and graph plan. Revalidate complete proposed invariants and all affected endpoint guards immediately before the sole attributable domain/result save.
  - Delete only the exact active occurrence and insert separate removal evidence atomically. Re-add gets fresh identity, no-op changes no timestamps/token, endpoint tokens change through incidence only. Retained replay remains first and read-only while dirty; keep uncertainty/reconciliation and enablement guards intact.
  - Blocked-by: ev1ktl8 (Red: test protected standalone link create/update integration), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [1.3](requirements.md#1.3), [3.2](requirements.md#3.2), [3.5](requirements.md#3.5), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [7.3](requirements.md#7.3), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md

- [x] 15. Red: test ordinary query filters, frozen detail and modern result parity <!-- id:ev1ktla -->
  - Write TaskLinkQueryTests for hasLinks/type/opposite UUID/direction/unblocked plus existing selectors, incoming duplicate direct targets, complete blocker assessments and unsupported/conflicting options.
  - Test certified blocked-only unblocked:false, invalid matching neither value, scoped closure/count/order compatibility, frozen pages across edits/imports/expiry, missing graph coverage, reused graph options rejected before publication, and semantic text/structured parity.
  - Assert query/output descriptions cover saved-only scope, blockers/canonical resolution, body omission versus empty incidence, new r1 coverage/old-token conflicts, immutable historic receipts and explicit missing historic graph coverage.
  - Blocked-by: ev1ktl9 (Green: implement protected standalone link create/update integration), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [x] 16. Green: implement ordinary query filters, frozen detail and modern result parity <!-- id:ev1ktlb -->
  - Wire MCPToolHandler+TaskQuery/definitions to the saved frozen graph and prepared tool result; add links/diagnostics/duplicateResolution/blockerAssessment while preserving authoritative tokens when bodies omitted.
  - Integrate T-2383 frozen encoder fragment and existing T-63 publication gates. T-2382 reusable project/status queries stay unchanged and reject graph options; no live enrichment, broadened selection/counts or guessed navigation URLs.
  - Describe saved-only scope, revision coverage transition, blocker/canonical rules, missing historic graph coverage and supported navigation directly in published tool/output contract guidance.
  - Blocked-by: ev1ktla (Red: test ordinary query filters, frozen detail and modern result parity), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [x] 17. Red: test seven-day repair evidence expiry and clean maintenance <!-- id:ev1ktlc -->
  - Write TaskLinkRemovalEvidenceTests with both active/evidence import arrival orders, frozen versus fresh evaluation at seven-day expiry, content-token stability, changed evidence-based diagnostics/derived assessments, re-add identity and original-key receipt independence.
  - Verify cleanup affects only expired evidence, never active rows/framework history or UI drafts; future/malformed dates and ambiguous evidence identity defer; post-expiry unknown selectors fail closed, live reads/preview never run cleanup.
  - Blocked-by: ev1ktlb (Green: implement ordinary query filters, frozen detail and modern result parity), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [6.4](requirements.md#6.4), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [x] 18. Green: implement seven-day repair evidence expiry and clean maintenance <!-- id:ev1ktld -->
  - Implement seven-day evidence recognition/expiry and a bounded maintenance hook in TaskLinkService using its own clean autosave-disabled context. Preserve actual platform occurrence deletion and do not add a custom tombstone or history purge protocol.
  - Wire maintenance to an existing safe owned lifecycle hook, outside read/preview/graph commit. Remove only eligible evidence after fresh identity revalidation; stale completion/cleanup must not alter retained graph or imply retry/convergence safety.
  - Blocked-by: ev1ktlc (Red: test seven-day repair evidence expiry and clean maintenance), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [6.4](requirements.md#6.4), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [-] 19. Red: test saved native relationship visibility and unique navigation <!-- id:ev1ktle -->
  - Write TaskLinkNativeProjectionTests and focused automated UI/navigation tests for saved endpoint labels under unsaved drafts, unsaved source unavailable, missing/colliding destination UUIDs, saved import refresh and cancellation of stale task/generation completions.
  - Assert no first-match navigation at click or TaskDetailWindowView resolution; read-only incident direction/canonical diagnostics use the existing iOS/macOS detail patterns.
  - Blocked-by: ev1ktld (Green: implement seven-day repair evidence expiry and clean maintenance), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.5](requirements.md#1.5), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [5.3](requirements.md#5.3), [6.3](requirements.md#6.3), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [ ] 20. Green: implement saved native relationship visibility and unique navigation <!-- id:ev1ktlf -->
  - Wire TaskLinkService.savedDetail and Views/TaskDetail/TaskLinksSection into TaskDetailView Form/LiquidGlassSection, using saved value DTOs and existing exact UUID window/iOS detail navigation.
  - Revalidate unique saved destination at selection and macOS window resolver; unresolved targets remain diagnostics. Cancel stale refresh output; no link editor, merge/closure/undo, guessed URLs or App Intent parity.
  - Blocked-by: ev1ktle (Red: test saved native relationship visibility and unique navigation), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.5](requirements.md#1.5), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [5.3](requirements.md#5.3), [6.3](requirements.md#6.3), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [ ] 21. Red: test integrated regression and schema-contract verification <!-- id:ev1ktlg -->
  - Add focused disk/multi-context regression fixtures tying schema upgrade, protected create/update/repair, revision coverage, frozen captured queries, batch rejection, retention and native navigation together in TaskLinkFoundationIntegrationTests.
  - Assert non-link tool field/status/comment/retry semantics, unchanged T-2382 counts/lifecycle, T-2383 parity/historic bytes and T-63 failure/publication limits. Use synthetic/copy test stores and no production repair/reset.
  - Blocked-by: ev1ktlf (Green: implement saved native relationship visibility and unique navigation), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md

- [ ] 22. Green: implement integrated regression and schema-contract verification <!-- id:ev1ktlh -->
  - Complete shared service/app/tool schema wiring and minimum corrective code exposed by integration fixtures; repeat the final-base parity audit against every schema/snapshot consumer and fill missed equivalent callsites.
  - Run only focused affected tests first, then repository-required lint/build/unit/simulator checks through parent heavy-test queue with per-command approval. Preserve all non-goals; failures return to the responsible pair/design gate, not retries against live records or relaxed owned-save protections/budgets.
  - Blocked-by: ev1ktlg (Red: test integrated regression and schema-contract verification), ev1ktkx (Green: implement pre-feature store migration and schema parity), ev1ktkz (Green: implement coordinated saved validation and owned receipt commitment), ev1ktl3 (Green: implement bounded saved capture and graph-closure capacity)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3)
  - References: design.md, requirements.md, decision_log.md
