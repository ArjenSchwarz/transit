---
references:
    - specs/safe-task-consolidation/requirements.md
    - specs/safe-task-consolidation/design.md
    - specs/safe-task-consolidation/decision_log.md
metadata:
    approval: approved-5921d795
    design: approved-7714e301
    execution: phase-1-complete-awaiting-parent-review
---
# Safe task consolidation implementation tasks

## Local durability foundations

- [x] 1. Red: test immutable history encoding, limits and closed-store migration <!-- id:eiyvabh -->
  - In TransitTests/TaskConsolidationHistoryTests.swift and TaskConsolidationMigrationTests.swift, use owning TestModelContainer fixtures and an exact prior eight-entity closed disk store; assert reopen preserves tasks/comments/links/receipt bytes and adds only the event entity.
  - Specify event scalar/default/optional/no-unique/no-cascade shape; version/index/payload validation, physical collision/multiple reversal diagnostics, exact raw date/metadata restoration evidence, deterministic o1 and apply/undo history beyond seven days.
  - Test UTF-8 payload immediately below/at/above 256 KiB and bounded changed-value/accounting fixtures. These tests must fail for the absent event/codec; no production store or CloudKit mutation.
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [8.1](requirements.md#8.1)
  - References: design.md, requirements.md, decision_log.md

- [x] 2. Green: implement bounded immutable history and additive schema integration <!-- id:eiyvabi -->
  - Add Models/TaskConsolidationEvent.swift and Services/TaskConsolidation history value/codec/o1 components; use immutable scalar participant slots and validated versioned payload with the approved 256-KiB limit.
  - Register only the new entity in TransitApp/current TestModelContainer schemas; retain intentional old migration fixture schemas. Reopen and prove the paired old-store tests, preserved bytes and non-expiring history.
  - Wire codec/history projection into owned fixture services for subsequent steps. A failed local migration stops dependent work for design correction; no production schema promotion or persistence redesign.
  - Blocked-by: eiyvabh (Red: test immutable history encoding, limits and closed-store migration)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [8.1](requirements.md#8.1)
  - References: design.md, requirements.md, decision_log.md

- [x] 3. Red: test one owned group/history/receipt commitment and recovery <!-- id:eiyvabj -->
  - Add TaskConsolidationOwnedCommitTests.swift using the real MCPWriteCoordinator/MCPWriteCommitScope with deterministic reviewed-plan fixtures: multiple task/status changes, actual link occurrences, one history event and one terminal receipt must share a save and survive independent reopen.
  - Inject pre-save encoding/capacity failure, save failure, accepted interruption, lost response and unavailable durability probes; require proven all-or-none local outcomes and truthful uncertainty. Cover clean checks before acceptance and every post-await success/error, dirty replay without saves/rollback, and participating noninterleave.
  - Define typed group command/owned service interfaces needed by these fixtures; RED may fail on absent interfaces. Outside-container/import counterexamples are acknowledged allowed races, never a required global fence.
  - Blocked-by: eiyvabi (Green: implement bounded immutable history and additive schema integration)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [6.3](requirements.md#6.3), [8.1](requirements.md#8.1)
  - References: design.md, requirements.md, decision_log.md

- [x] 4. Green: extend the existing protected coordinator with owned group execution <!-- id:eiyvabk -->
  - Extend MCPWriteCommand/PreparedMCPWrite and MCPWriteCommandServices/MCPWriteCommitServices with group cases and TaskConsolidationService; consolidation adapter supplies the existing clean owned-context policy/factory.
  - Implement the minimum no-save group execution and actual staged evidence path exercised by deterministic review fixtures; extend TaskLinkOwnedApply to return inserted/removed occurrence values while preserving standalone callers. Compute staged r1/o1 and terminal/history from the same values before one save.
  - Pass paired fault/reopen and dirty-context controls using the real coordinator. Keep production tool registration for final integration; an absent full planner/review capability must be unavailable, not bypassed. No second coordinator, per-item keys or compensation.
  - Blocked-by: eiyvabj (Red: test one owned group/history/receipt commitment and recovery)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [6.3](requirements.md#6.3), [8.1](requirements.md#8.1)
  - References: design.md, requirements.md, decision_log.md

## Consolidation integration

- [ ] 5. Red: test explicit preservation planning and attributable undo properties <!-- id:eiyvabl -->
  - Write TaskConsolidationPlannerTests.swift with seeded Swift Testing generators and an independent reference for unchanged input/unrelated content, combined proposed graph deltas and eligible apply-to-undo changed-field/graph restoration.
  - Cover one-to-five candidates, UUID normalization/repeats/self-selection/physical ambiguity, unique same-project physical identity, terminal canonical survivor, valid retained chains versus different/missing/cyclic targets, mixed source-accounting and complete metadata replacement/description null versus omission.
  - Assert unfinished-only closure policy and commit-time date/ID markers, strict statusRawValue/metadataJSON rejection, unconditional acknowledgment including retention-only plans, and undo guards for current content/evidence rather than temporal ABA detection.
  - Blocked-by: eiyvabi (Green: implement bounded immutable history and additive schema integration)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: design.md, requirements.md, decision_log.md

- [ ] 6. Green: implement value-only group and reversal planning <!-- id:eiyvabm -->
  - Add Services/TaskConsolidation/ConsolidationPlanner and strict request/accounting value validators; bind caller reason/dispositions and optional survivor edits to exact selected originals and combined graph rules.
  - Produce only permitted deltas; retain existing canonical chains/incoming relationships, preserve original assignments/comments, reject raw corrupt evidence and missing attribution without semantic summarization.
  - Implement history-based reversal planning/current-availability projection over codec values and complete dependency evidence, including already-reversed/ambiguous history and exact attributable raw fields/status dates/created occurrences. Wire these planners into fixture service dependencies.
  - Blocked-by: eiyvabl (Red: test explicit preservation planning and attributable undo properties)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)
  - References: design.md, requirements.md, decision_log.md

- [ ] 7. Red: test shared read lifecycle and complete saved history closure <!-- id:eiyvabn -->
  - Add TaskConsolidationCaptureTests.swift and lifecycle tests using saved contexts and original admission clocks: selected participant history requires all operation participants, comments/incidences/canonical paths and physical event multiplicity within one stable saved boundary.
  - Cover pending UI inserts/edits/deletions, comment/history storage/decode failures, unknown versions/missing or ambiguous closure, original selection unchanged by supplementary dependencies, legacy absent coverage versus current observed empty history, and stable capture invalidation.
  - Specify eight shared unfinished native/MCP reads, five-second original deadline, cancellation/timeout retaining physical capacity until cleanup, listener-scoped stop/restart preserving native admission, and complete six-ticket/long-history/full-envelope 16-MiB boundaries. No partial review or hidden truncation.
  - Blocked-by: eiyvabi (Green: implement bounded immutable history and additive schema integration), eiyvabk (Green: extend the existing protected coordinator with owned group execution), eiyvabm (Green: implement value-only group and reversal planning)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [4.4](requirements.md#4.4), [5.4](requirements.md#5.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md

- [ ] 8. Green: integrate shared admission and saved participant/history capture <!-- id:eiyvabo -->
  - Expose the existing MCPReadCoordinator Foundation lifecycle/value-result entry across platforms; TransitApp owns one lifetime and listener admission tags keep MCPServer cancellation scoped. Keep transport/provider adapters macOS-gated and retain physical cleanup accounting.
  - Extract/reuse the existing persistent-history/generation saved boundary for MCP and native consolidation capture, add event empty-store proof, immutable values and byte charges, and capture complete supplementary participant/comment/incidence/canonical/event closure.
  - Extend fresh full query projection with mandatory history/current undo assessment and explicit unavailable/over-limit outcomes; legacy retained results are unchanged. Pass paired bounded capture/lifecycle tests before preview/write integration; native extraction creates no second counter/timer/snapshot engine.
  - Blocked-by: eiyvabn (Red: test shared read lifecycle and complete saved history closure)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [4.4](requirements.md#4.4), [5.4](requirements.md#5.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md

- [ ] 9. Red: test retained previews and their exact publication contract <!-- id:eiyvabp -->
  - Add TaskConsolidationPreviewTests.swift and ReviewRetentionTests.swift for complete original/accounting/change/graph readback, strict preview inputs with no write key and no domain/history/receipt/retry/timestamp/display-ID effects.
  - Specify ordinary-index reviewId/p1/local-scope/kind matching, five-minute expiry without consumption/extension, all index rebuild/purge/clear paths, eight-root/16-MiB full-representation accounting and response-gated publication.
  - Fault response encoding/publication, cancellation and original deadline before review visibility; expired/restarted/cleared reviews must not authorize fresh apply. Boundary-sized previews must either fit completely or return unavailable. Include undo preview from recorded operation evidence.
  - Blocked-by: eiyvabm (Green: implement value-only group and reversal planning), eiyvabo (Green: integrate shared admission and saved participant/history capture)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [4.1](requirements.md#4.1), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [7.1](requirements.md#7.1), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md

- [ ] 10. Green: implement bounded previews on the ordinary retained-read path <!-- id:eiyvabq -->
  - Add MCP/Consolidation preview adapters and immutable review entries to MCPTaskQuerySnapshotStore.Index; preserve entries in every rebuild and retire them with descriptor roots. Reuse shared publication reservation/terminal selection and canonical p1.
  - Implement consolidation/undo preview projection with server-held exact input/evidence/deltas; no editable client plan or durable preview rows. Return review references only after complete response preparation/publication.
  - Wire preview adapters into injected handler/read-service test paths and route complete saved evidence through the planners; keep production advertised wiring for final integration. Pass retained capacity/deadline/expiry and no-write tests.
  - Blocked-by: eiyvabp (Red: test retained previews and their exact publication contract)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [4.1](requirements.md#4.1), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [7.1](requirements.md#7.1), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md

- [ ] 11. Red: test protected reviewed apply against current saved evidence <!-- id:eiyvabr -->
  - Write TaskConsolidationApplyTests.swift through the real coordinator and injected review source: acknowledgment and exact reviewId/p1/scope/kind are mandatory; stale task/comment/incidence/canonical evidence and unique common-project failures reject the whole group.
  - Specify all six participants preserved, unfinished closures with existing StatusEngine dates, terminal/survivor dates untouched, survivor edited fields only, combined graph validation before effects and retained pre-existing chains/unselected content.
  - Assert actual allocated occurrence tuples feed staged r1 and inserted event feeds staged o1; exceed event/result limits before commit, inject final-save/recovery faults and participating interleave attempts. Unrelated outside imports may race; actual saved result/diagnostics remain truthful.
  - Blocked-by: eiyvabk (Green: extend the existing protected coordinator with owned group execution), eiyvabm (Green: implement value-only group and reversal planning), eiyvabo (Green: integrate shared admission and saved participant/history capture), eiyvabq (Green: implement bounded previews on the ordinary retained-read path)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [7.1](requirements.md#7.1), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md

- [ ] 12. Green: complete consolidation apply in the owned group service <!-- id:eiyvabs -->
  - Replace deterministic fixture-only planning with current saved participant/comment/link/canonical resolution and exact retained proposal validation in TaskConsolidationService/MCPConsolidationWriteAdapter's final synchronous phase.
  - Apply only reviewed fields/unfinished statuses and combined link delta; use actual returned occurrence values, exact raw reversible values and staged r1/o1 for bounded immutable event plus committed result in the existing one-save receipt path.
  - Integrate strict acknowledgment/domain errors and actual mappings/undo assessment in test handler paths; no nested mutate_tasks calls, all-writer fence, implicit canonical redirection or UI draft publication.
  - Blocked-by: eiyvabr (Red: test protected reviewed apply against current saved evidence)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [7.1](requirements.md#7.1), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md

- [ ] 13. Red: test reviewed whole undo and persistent reversal history <!-- id:eiyvabt -->
  - Add TaskConsolidationUndoTests.swift for exact retained reversal/evidence/o1 and all applied participant r1s; comment/incident-link/content differences, missing originals/events, physical collisions, stale preview and graph-rule failures reject the whole reversal.
  - Specify exact raw survivor/status/date restoration and only consolidation-created occurrence removal with existing removal evidence; pre-existing links/comments/assignments/history/receipt bytes survive. Add seeded round-trip and unrelated-record invariants alongside concrete terminal/no-edit/mixed-disposition fixtures.
  - Inject shared dirty-context, one-save reversal/event/receipt faults and uncertainty; verify one unique reversal, exact retained undo replay, fresh-key already_reversed reconciliation and no reversal inferred from missing/expired receipts or evidence.
  - Blocked-by: eiyvabs (Green: complete consolidation apply in the owned group service)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [7.1](requirements.md#7.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md

- [ ] 14. Green: implement exact reversal and already-reversed reconciliation <!-- id:eiyvabu -->
  - Complete TaskConsolidationService.undo with current exact review/task/operation/link checks, combined reversal graph validation and raw field/status-date restoration; remove exact created occurrences through existing owned removal handling.
  - Save reversal event and terminal result with all attributable effects once; derive o1 from staged events and preserve original event/history. Multiple/unknown/conflicting history fails closed.
  - Handle valid already_reversed from saved history without requiring a now-expired review, while exact terminal replay still precedes all current checks. Reuse originating-store retry/recovery and outside-writer limitations; no force/selective undo or abandoned-to-Idea shortcut.
  - Blocked-by: eiyvabt (Red: test reviewed whole undo and persistent reversal history)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [7.1](requirements.md#7.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md

- [ ] 15. Red: test modern tool contracts, historical replay and recovery envelopes <!-- id:eiyvabv -->
  - Add TaskConsolidationWireResultTests.swift using injected handlers with all four private tool definitions: strict nested schemas/no unknown fields, correct read-only/protected classification, structured/text equality, known task participant positions and operation IDs without navigation links.
  - Assert original-key byte-identical replay after edits/deletion/review expiry/restart, changed-payload reuse rejection, accepted/active/interrupted/uncertain outcomes, seven-day receipt expiry separate from permanent operation history, and retained legacy page/token bytes unchanged.
  - Inject complete-wrapper failure before/after effects and require prepared compact recovery bytes with known tool/key/operation identity, no unbounded participant bodies or invented no effect. Preserve mutate_tasks/App Intent and generic r1 contracts.
  - Blocked-by: eiyvabq (Green: implement bounded previews on the ordinary retained-read path), eiyvabs (Green: complete consolidation apply in the owned group service), eiyvabu (Green: implement exact reversal and already-reversed reconciliation)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [8.1](requirements.md#8.1)
  - References: design.md, requirements.md, decision_log.md

- [ ] 16. Green: implement strict schemas and modern consolidation result adapters <!-- id:eiyvabw -->
  - Add MCP/Consolidation strict input/output definition builders and MCPResultSchemas/MCPModernProviderBinding/MCPResultLinks integration; previews are covered reads and apply/undo protected group writes in injected test registration.
  - Prepare bounded committed participant/mapping/operation envelopes and pre-effect compact recovery identities through the existing provider seam; operation IDs remain source evidence, task references reuse current unavailable navigation presentation.
  - Pass paired replay/expiry/failure tests without reminting old pages/receipts/r1 tokens; do not add link/group operations to mutate_tasks, new navigation URLs or live client setup.
  - Blocked-by: eiyvabv (Red: test modern tool contracts, historical replay and recovery envelopes)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [8.1](requirements.md#8.1)
  - References: design.md, requirements.md, decision_log.md

- [ ] 17. Red: test native saved history presentation and safe navigation <!-- id:eiyvabx -->
  - Write TaskConsolidationNativeStateTests.swift and automated task-detail UI tests for reason, original/survivor references, changes/dispositions, reversal state and explicit unavailable/over-limit history in every existing detail layout.
  - Exercise the shared saved value provider/physical admission with source changes, cancellation, save/import notification bursts and 100-ms coalescing; stale values must not publish, listener restart must not suppress native reads.
  - Use deterministic history-bearing UI fixtures; exact unique saved navigation works and missing/duplicate physical task references remain diagnostics. Assert no native consolidation editing/apply/undo controls.
  - Blocked-by: eiyvabo (Green: integrate shared admission and saved participant/history capture), eiyvabu (Green: implement exact reversal and already-reversed reconciliation)
  - Stream: 1
  - Requirements: [3.3](requirements.md#3.3), [6.4](requirements.md#6.4), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [8.1](requirements.md#8.1)
  - References: design.md, requirements.md, decision_log.md

- [ ] 18. Green: add native read-only consolidation history and deterministic fixtures <!-- id:eiyvaby -->
  - Implement TaskConsolidationHistorySection beside TaskLinksSection in all TaskDetailView layouts, using shared saved capture/value state, existing source/generation invalidation/coalescing and TaskLinkNavigationResolver.
  - Show history details/current unavailable assessments using existing link diagnostics/reference affordances; keep original UUID navigation and no guessed URLs or mutation controls.
  - Add the deterministic consolidation history UITestScenario and fixture records needed by paired automated tests, preserving default app startup and user data. Wire native provider to app-owned coordinator on all platforms.
  - Blocked-by: eiyvabx (Red: test native saved history presentation and safe navigation)
  - Stream: 1
  - Requirements: [3.3](requirements.md#3.3), [6.4](requirements.md#6.4), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [8.1](requirements.md#8.1)
  - References: design.md, requirements.md, decision_log.md

- [ ] 19. Red: test the fully composed six-ticket application workflow <!-- id:eiyvabz -->
  - Add TaskConsolidationEndToEndTests.swift against the real TransitApp-style handler/service factory and advertised tool list, not injected registration: preview a survivor plus five same-project candidates with conflicting descriptions/metadata, mixed statuses/comments and retained canonical chains, then apply/read/undo-preview/undo.
  - Assert every unique detail has explicit accounting, originals/history remain inspectable, resulting mappings/actual dates/raw fields round-trip, unselected tasks/relationships and original receipt/page bytes remain unchanged. Include no-edit/terminal groups, stale review, over-limit and lost-response original-key recovery.
  - Exercise composed native/MCP admission and listener restart, physical cleanup, all current schema registrations and pending-draft isolation. These tests are RED until final production construction/registration uses the completed feature; no live service or CloudKit fixture.
  - Blocked-by: eiyvabq (Green: implement bounded previews on the ordinary retained-read path), eiyvabs (Green: complete consolidation apply in the owned group service), eiyvabu (Green: implement exact reversal and already-reversed reconciliation), eiyvabw (Green: implement strict schemas and modern consolidation result adapters), eiyvaby (Green: add native read-only consolidation history and deterministic fixtures)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md

- [ ] 20. Green: wire the completed feature into application and advertised MCP tools <!-- id:eiyvac0 -->
  - Connect TransitApp/app-owned coordinator, complete consolidation service/review source, MCPReadAppDependencies, MCPToolHandler routing/allowlist and MCPToolDefinitions.coreTools to the four completed contracts; preserve listener-scoped lifecycle and current schemas.
  - Use actual application construction in paired composed tests so absent capabilities fail unavailable rather than expose fixture-only or bypass execution. Finish any concrete integration defects shown by those tests; all components must have real consumers.
  - Run appropriate focused and final repository-required automated checks only after implementation authorization and an available heavy slot; failures require code fixes, not test weakening. No deployment, production schema promotion, live ticket mutations, client activation or all-writer proof is part of completion.
  - Blocked-by: eiyvabz (Red: test the fully composed six-ticket application workflow)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: design.md, requirements.md, decision_log.md
