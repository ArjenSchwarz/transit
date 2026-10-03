---
references:
    - specs/bounded-read-freshness/requirements.md
    - specs/bounded-read-freshness/design.md
    - specs/bounded-read-freshness/decision_log.md
---
# T-63 bounded read freshness implementation

- [ ] 1. Define shared read contracts and injection seams on the merged foundation <!-- id:vh146y0 -->
  - Types/interfaces-only exemption. Before these edits, align only this clean dedicated branch to merged foundation 201205bd4e786c7f152d8f99006b37da7da888c7; preserve all other worktrees and the approved spec commits. Do not modify T2380.
  - Create macOS-gated explicitly nonisolated Sendable DTO/protocol definitions in Transit/Transit/MCP/Reads and optional MCPToolResult metadata. Define typed ReadCaptureScope, CaptureCompleteness, LocalRecordKey, CapturedReadView, MCPRetainedViewSource, MCPPreparedPublication validation/commit/discard, PreparedReadResult and PreencodedPublicationErrors.
  - T-63 alone owns MCPServer, shared handler init/dispatch/readOnlyToolNames, existing/common schema wiring and MCPTypes. Confirm these interfaces with T2382; it supplies separate summary/query/schema/store modules. No portfolio aggregation or reusable lifecycle implementation here.
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.6](requirements.md#2.6), [5.3](requirements.md#5.3)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 2. Red: add saved-capture and persistent-history feasibility tests <!-- id:vh146y1 -->
  - Add MCPReadCaptureBuilderTests using owning TestModelContainer fixtures and disposable on-disk CloudKit-free stores. Fail for missing fresh-context capture: saved writes visible, pending UI edits absent, project selector resolved inside fence, frozen relationships/physical keys, mixed save between fetches rejected.
  - Add history-fence tests for empty domain versus empty selection, purged/expired/unavailable history, mismatched store IDs and multi-entity saves; missing required comment/revision evidence fails rather than empty success.
  - Add a signed-store observation test harness for real CloudKit import/history visibility using existing configured storage without synthetic production writes. Record supported proof versus documented incoherent_capture outcome; do not claim the isolated local probe establishes remote coherence.
  - Blocked-by: vh146y0 (Define shared read contracts and injection seams on the merged foundation)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.6](requirements.md#2.6), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [5.3](requirements.md#5.3)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 3. Green: implement and verify the fenced saved capture builder <!-- id:vh146y2 -->
  - Implement MCPReadCaptureBuilder and history fence: initial fresh-context latest history watermark, fresh autosave-disabled capture context, synchronous nonawaiting MainActor DTO copy, final fresh-context watermark and import generation check. Never save/rollback UI mainContext; no unbounded retries.
  - Validate complete declared portfolio/project scope plus identity/comment closure at construction and consumption; closure cannot expand totals/query scope. Preserve canonical MCPRecordSnapshot.task r1 with its authoritative UUID-based comment coverage before stripping output comments.
  - Run task 2 evidence with Xcode 27. Unsupported capture fencing fails incoherent_capture; unavailable import applicability stays unknown. If a different coherence mechanism is needed, stop dependent work and return that design change to parent. Dependent capture/projection tasks wait for this verified outcome.
  - Foundation risk gate A: establish saved capture/canonical revision behavior using actual SwiftData and merged MCPRecordSnapshot, with a minimal fixture adapter; no T2382 aggregation/store/helper code is required. Unknown/unavailable live evidence must be recorded honestly and use the approved fallback, not a fabricated proof.
  - Blocked-by: vh146y1 (Red: add saved-capture and persistent-history feasibility tests)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.6](requirements.md#2.6), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [5.3](requirements.md#5.3)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 4. Red: add import-evidence and bounded-refresh policy tests <!-- id:vh146y3 -->
  - Add MCPImportEvidenceMonitorTests and MCPReadRefreshPolicyTests with injected clocks, event source, store matching and capture-applicability proof. Cover unrelated/setup/export, queued callbacks, in-flight success/failure, retained last success, future/inconsistent wall clocks and30-second boundary.
  - Fail for missing policy: cached/default/inactive, invalid enum/type precedence, recent-import skip, unsupported trigger/no in-flight immediate unavailable,two-second/remaining/zero wait, observed success>failed>timeout>unavailable and total timeout precedence.
  - Use synthetic evidence only in tests; production must never infer store match/import visibility from heartbeat, local save or notification arrival time.
  - Blocked-by: vh146y0 (Define shared read contracts and injection seams on the merged foundation)
  - Stream: 2
  - Requirements: [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 5. Green: implement import monitoring and the bounded refresh decision <!-- id:vh146y4 -->
  - Implement serialized non-MainActor MCPImportEvidenceMonitor callback-value copying and monotonic freshness classifier, plus refresh adapter explicitly unavailable for current SwiftData API. Use launch-fixed SyncManager mode; observe only positively relevant already-in-flight imports.
  - Wire capture-applicability seam to task 1 contracts and validate with task 4. Unknown/null evidence is the supported fallback when matching or visibility cannot be proved; inactive skips waiting. Stop observer cleanly without letting delayed callbacks relabel frozen capture metadata.
  - This module can run in parallel with tasks2–3 because it owns separate files/test doubles; live signed-store verification is coordinated through parent and final integration requires task 3.
  - Blocked-by: vh146y3 (Red: add import-evidence and bounded-refresh policy tests)
  - Stream: 2
  - Requirements: [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 6. Red: add deadline, physical permit and transport feasibility tests <!-- id:vh146y5 -->
  - Add MCPReadCoordinatorTests and a minimal router-return test harness using controllable physical workers. Require encoded timeout availability withinfive seconds duringsix-second MainActor blocking;eight lingering permits/ninth busy; single winner on cancellation/timeout/success/stop/restart.
  - Add seeded generated event-sequence tests for response count, generation, no late publication, unfinished count0–8 and atomic capture-to-assembly permit transfer. Distinguish notification/no-response from admission accounting.
  - Fail for missing independent timer/batch gate: long IDs and existing1 MiB body ceiling, many invalid/busy elements, prebuilt whole-array fallback and blocked large candidate serialization. Admission time precedes fallback preparation; measure router-return availability, not just timer firing.
  - Blocked-by: vh146y0 (Define shared read contracts and injection seams on the merged foundation)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [6.2](requirements.md#6.2)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 7. Green: implement independent deadline and physical admission coordination <!-- id:vh146y6 -->
  - Implement process-lifetime lock-based MCPReadCoordinator,8physical permits, generation/terminal gates, explicit@concurrent continuation path and strict zero-leeway timer at admission+4,850 ms. Route awaits response gate; worker finalizer alone releases its permit.
  - Implement whole read-only batch preencoded fallback, common admission timestamp, private candidate aggregation and retained assembly permit. Mixed delivery preserves write order/approved exception; expired undispatched reads must not start fetches.
  - Pass task 6 early transport/load harness before building dependent publication/routing. Scheduling evidence is empirical; tune internal cutoff earlier within approvedfive seconds if necessary without weakening the guarantee or resetting admission time. No structured cleanup await or MainActor timeout.
  - Foundation risk gate B: test the actual Hummingbird router/encoded-response adapter with fixture read work, blocked MainActor and large fallback preparation before T2382 modules exist. This independently proves transport mechanics; cross-ticket handlers are only a final acceptance dependency.
  - Blocked-by: vh146y5 (Red: add deadline, physical permit and transport feasibility tests)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [6.2](requirements.md#6.2)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 8. Red: add atomic publication and ordinary-cursor race tests <!-- id:vh146y7 -->
  - Add MCPReadPublicationDomainTests with test retention participants and ordinary MCPTaskQuerySnapshotStore. Cover pending+visible capacity, expiry between lookup/append, stale CAS=>READ_BUSY, collision allocation, v4 ordinary/v8 reusable routing after expiry.
  - Fail for missing aggregate transaction: two creates, two appends and create+append in the same store/batch, concurrent independent requests, child-to-aggregate reservation transfer without gap/double count; validate all candidates before any commit and swap each store once.
  - Generated timeout/stop/disconnect/success races require exactly-once discard, no IDs in chosen success without publication, no child publication before selected whole batch, preencoded rejection selection and large-copy/destruction outside domain lock.
  - Assert charged capacity numerically: child-to-aggregate transfer preserves the total charge, and each rollback returns the original charge exactly once.
  - Blocked-by: vh146y2 (Green: implement and verify the fenced saved capture builder), vh146y6 (Green: implement independent deadline and physical admission coordination)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [1.6](requirements.md#1.6), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 9. Green: implement shared publication domain and migrate ordinary retention <!-- id:vh146y8 -->
  - Implement common T63-owned MCPReadPublicationDomain and immutable prepared reservation/candidate machinery. Coalesce selected same-store changes outside gate, atomically transfer reservation ownership, validate complete selected set and terminal/generation/cutoff, then nonthrowing swaps plus encoded-response selection.
  - On validation rejection choose prepared matching error or whole-batch fallback; discard all unselected reservations exactly once. No fetch/encoding/callback/nestedstorelock/bulkindexcopy or final large destruction under gate.
  - Migrate ordinary task-query retention to the domain while preservingeight snapshots/16 MiB/300 seconds and original metadata bytes. T2382 owns its separate8views/16 MiB store and hooks; do not implement or edit that store independently. Run task 8.
  - Two-way handoff: after task 3 saved/canonical risk proof, task 7 transport risk proof and task 9 shared publication tests pass, give parent the verified local foundation commit and interface/test evidence for T2382 to consume. This handoff has NO T2382 module dependency. T2382 then implements separate modules while T63 continues tasks 10–15; actual cross-ticket acceptance waits until tasks 13/16. No remote push/publication is implied by this local handoff.
  - Blocked-by: vh146y7 (Red: add atomic publication and ordinary-cursor race tests)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [1.6](requirements.md#1.6), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 10. Red: add read projection, wire parity and frozen metadata tests <!-- id:vh146y9 -->
  - Add focused handler tests for task single/batch/list/cursor and project/milestone scoped/empty/detail reads. Assert existing text payload/filter/order/identifier-error precedence, metadata namespace/UTCms/asOf=assessedAt, full record canonical r1 with comments hidden, and summary no-comment-fetch parity.
  - Inject required fetch/history/comment/serialization failure, incomplete captures, unknown/stale/failing imports and valid empty success; assert machine categories and no fabricated identity/time.
  - Test frozen metadata byte-for-byte across imports/local edits/cursor retries, no new wait/refetch, malformed policy before lookup and typed conflict after valid lookup. Add shared-view source fixture proving identical snapshot identity/evidence and SNAPSHOT_INCOMPATIBLE outside declared scope.
  - Cursor policy fixtures explicitly cover omitted policy, an explicit matching retained policy, malformed policy before lookup, and a well-typed conflict after valid lookup.
  - Blocked-by: vh146y2 (Green: implement and verify the fenced saved capture builder), vh146y4 (Green: implement import monitoring and the bounded refresh decision), vh146y8 (Green: implement shared publication domain and migrate ordinary retention)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [3.1](requirements.md#3.1), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 11. Green: migrate covered handler reads onto captured DTO projection <!-- id:vh146ya -->
  - Update MCPToolHandler+TaskQuery and query_milestones/get_projects paths to capture/project immutable DTOs, typed policy parsing, prepared encoded results and additive outer metadata. Preserve ordinary UUID selector semantics and T2380 writes/canonical r1; physical attribution is for shared capture, not a query semantic rewrite.
  - Freeze complete original metadata in ordinary retained pages; replay without capture/wait. Map read execution errors to approved existing/extended codes and metadata categories; input/cursor/capacity precedence stays unchanged.
  - Use injected MCPRetainedViewSource for reusable views and keep T2382 snapshot-query implementation separate. Integrate minimum code and task 10 tests together; no fallback empty arrays.
  - Blocked-by: vh146y9 (Red: add read projection, wire parity and frozen metadata tests)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [3.1](requirements.md#3.1), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 12. Red: add full routing, lifecycle and T2382 integration tests <!-- id:vh146yb -->
  - Extend MCPServer tests for single/read-only/mixed JSONRPC, invalid arguments, notifications/all-notification HTTP 202, stopped service and restart with unfinished work; assert final encoded bytes and publication match terminal selection.
  - Add shared helper contract tests for T2382 descriptor registration, portfolio read classification, snapshotId dispatch, same view identity/evidence, scoped rejection and per-store batch aggregation. Use fixtures until parent supplies approved T2382 modules; integrated acceptance cannot pass on fixtures alone.
  - Write preservation regressions for merged write safety inputs/outputs/receipts/revisions, fallback-storage mutating allow-list and maintenance tools outside freshness scope.
  - Foundation tasks 1–9 never depend on these integration tests or on T2382 modules. Keep fixture-based red tests separate from actual-module final acceptance to avoid a circular cross-ticket gate.
  - Blocked-by: vh146y6 (Green: implement independent deadline and physical admission coordination), vh146y8 (Green: implement shared publication domain and migrate ordinary retention), vh146ya (Green: migrate covered handler reads onto captured DTO projection)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [4.4](requirements.md#4.4), [5.3](requirements.md#5.3), [6.2](requirements.md#6.2)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 13. Green: wire server lifecycle, common schemas and T2382 helpers <!-- id:vh146yc -->
  - T63 alone edits MCPServer routes/batch/start/stop, TransitApp construction, handler init/common dispatch/readOnlyToolNames, MCPToolDefinitions existing readPolicy/common provider wiring and shared MCPTypes. Inject one process-lifetime coordinator/monitor/publication domain and capture builder.
  - External prerequisite: parent delivers T2382 separate MCPToolHandler+PortfolioSummary, +SnapshotTaskQuery, MCPPortfolioToolDefinitions and retained-store hook modules matching approved interface. Wire query_tasks snapshotId dispatch to those helpers; do not duplicate their code or touch their worktree. Parent chooses clean dependency commit/cherry-pick after both task gates.
  - Run task 12 with actual modules. Keep write behavior/order, maintenance exclusion, encoded availability and atomic publication intact; never clear physical counts on generation changes.
  - Blocked-by: vh146yb (Red: add full routing, lifecycle and T2382 integration tests)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [4.4](requirements.md#4.4), [5.3](requirements.md#5.3), [6.2](requirements.md#6.2)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 14. Red: add nonblocking diagnostics and executable caller-contract tests <!-- id:vh146yd -->
  - Add diagnostic sink tests covering correlation and monotonic queue/refresh/capture/transform/serialization/batch durations, late completion/discard, bounded enqueue and simulated slow logging that cannot delay timeout/hold domain lock.
  - Add executable caller-example tests for new-query/new-capture versus cursor/same-capture, cached/default semantics, busy/timeout backoff, error mapping, no unbounded retry and mixed delivery caveat. Assert advertised MCP read descriptions expose these limits without changing payload shape.
  - Caller documentation creation remains an ancillary delivery requirement outside the skill's coding-only checklist; tests validate examples used in that guide.
  - Blocked-by: vh146yc (Green: wire server lifecycle, common schemas and T2382 helpers)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 15. Green: implement bounded phase diagnostics and caller-facing tool descriptions <!-- id:vh146ye -->
  - Implement bounded nonblocking diagnostic sink/event values with original operation correlation retained through late finalizer; measure actual elapsed stages without synchronous timer-path filesystem work or speculative CloudKit attribution.
  - Update code-level MCPToolDefinitions read descriptions/error guidance to match approved metadata/policy/deadline/import/backoff contracts and task 14 examples. Run task 14, including blocked logging.
  - Caller-guide creation and publication follow-up are tracked outside this coding-only checklist; pass the validated executable examples to that separate delivery step.
  - Blocked-by: vh146yd (Red: add nonblocking diagnostics and executable caller-contract tests)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md

- [ ] 16. Validate the integrated read contract and merged write parity with Xcode27 <!-- id:vh146yf -->
  - Test task 2–15 suites with actual T2382 integration and saved-only/whole-versus-scoped capture. Include real router-return timing under blocked MainActor/slow large encoding, frozen pages, event/import faults, process-lifetime accounting and atomic same-store batch cases; retain precise supported/unsupported live-history result.
  - Coordinate exclusive heavy build/simulator slot with parent before make lint/full macOS and required iOS gates; serialize SwiftData suites using owning fixtures. Xcode 27 only. If Makefile builds fail, use Xcode MCP when available and report exact unavailable capability; no downgrade or concurrent heavy worker.
  - Testing-only task; repairs reuse the adjacent red/green unit pair for the affected component before rerunning targeted acceptance. Full pre-push-review including Pulsar is mandatory afterwards under its separate skill; parent approval controls otherwise unauthorized publication, with no merge/deploy.
  - Blocked-by: vh146ye (Green: implement bounded phase diagnostics and caller-facing tool descriptions)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3)
  - References: specs/bounded-read-freshness/design.md, specs/bounded-read-freshness/decision_log.md
