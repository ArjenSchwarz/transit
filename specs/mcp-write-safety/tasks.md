---
references:
    - specs/mcp-write-safety/requirements.md
    - specs/mcp-write-safety/design.md
    - specs/mcp-write-safety/decision_log.md
---
# MCP Write Safety

- [x] 1. Red: Write disk durability and additive migration tests <!-- id:ztq9ldq -->
  - Add MCPWritePersistenceProbeTests, retained disk fixtures and a child-process termination test around save. Assert domain/status/comment and completed receipt persist together or neither; reopen an old-schema fixture, force save failure, and prove a later unrelated save leaves no ghost effects.
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [3.3](requirements.md#3.3), [5.4](requirements.md#5.4), [6.2](requirements.md#6.2)

- [x] 2. Green: Implement the receipt model and passing persistence probe <!-- id:ztq9ldr -->
  - Add Models/MCPWriteReceipt.swift with approved fields/defaults; register it in TransitApp and TestModelContainer and FallbackOutcomeFixture and full-schema sync fixtures; extend ModelContext+SafeRollback. Implement the temporary-store crash harness via a Makefile target. Stop and revise design if atomicity or migration or cleanup fails; this is the first integration gate. Verification: make test-mcp-write-persistence MCP_PROBE_SWIFT_FLAGS=-disable-sandbox passed actual-model old-schema migration plus SIGKILL before/after/during save plus read-only save failure and later-save ghost cleanup. Log: /tmp/t2380-storage-green.log. The compiler option disables only nested macro sandboxing; the outer runner sandbox remains active.
  - Blocked-by: ztq9ldq (Red: Write disk durability and additive migration tests)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [3.3](requirements.md#3.3), [5.4](requirements.md#5.4), [6.2](requirements.md#6.2)

- [x] 3. Red: Write canonical request and revision property tests <!-- id:ztq9lds -->
  - Add MCPCanonicalJSONTests and MCPRecordRevisionTests with deterministic generated nested JSON and object/comment permutations. Cover Boolean/number and absent/null distinctions, every covered scalar/assignment/comment field, excluded relationships, no-ops, exact dates, content restoration, and incomplete comment-fetch failure.
  - Blocked-by: ztq9ldr (Green: Implement the receipt model and passing persistence probe)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.3](requirements.md#2.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [6.2](requirements.md#6.2)

- [x] 4. Green: Implement canonicalization and snapshot-derived revisions <!-- id:ztq9ldt -->
  - Create MCP/Writes/MCPCanonicalJSON.swift and MCPRecordSnapshot.swift and MCPRecordRevision.swift. Produce normalized records and r1 SHA-256 tokens from one immutable capture with raw scalar coverage and exact date bits and stable UUID ordering. Retain canonicalizer versions for completed replay. Verification: make test-mcp-write-foundation MCP_PROBE_SWIFT_FLAGS=-disable-sandbox passed standalone production-code canonicalization/revision checks. Swift Testing suites include all entity scalars plus comment ordering and fetch failure; full app execution remains pending because package manifest diagnostic writes are blocked.
  - Blocked-by: ztq9lds (Red: Write canonical request and revision property tests)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.3](requirements.md#2.3), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [6.2](requirements.md#6.2)

- [x] 5. Red: Write durable guard, process lock and expiry recovery tests <!-- id:ztq9ldu -->
  - Add MCPLocalReservationStoreTests with temporary sidecars and two-process lock fixtures. Cover guard save/crash ambiguity, scope identity, key mismatch, missing receipts across restart, unreadable guards, lock reacquisition, fixed expiry/repair, both cleanup orders and unresolved guards beyond seven days.
  - Blocked-by: ztq9ldt (Green: Implement canonicalization and snapshot-derived revisions)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [5.5](requirements.md#5.5), [6.2](requirements.md#6.2)

- [x] 6. Green: Implement local guards and scoped receipt storage <!-- id:ztq9ldv -->
  - Create MCP/Writes/MCPLocalReservationStore.swift and MCPWriteReceiptStore.swift. Implement durable identity/guards and lifetime locking; scoped receipt reads plus duplicate detection and expiry repair/cleanup. Never expire unresolved bindings or infer rejection from missing records; keep domain results out of guards. Verification: standalone guards and foundation checks passed process lock contention/SIGKILL reacquisition plus unresolved payload retention and mismatched payload rejection and corrupt guard failure and fixed expiry and receipt staging/durable lookup and terminal cleanup repair. make lint passed with zero violations. make test-quick and configured Xcode fallback were blocked by runner permissions; app Swift Testing suites remain pending.
  - Blocked-by: ztq9ldu (Red: Write durable guard, process lock and expiry recovery tests)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [5.5](requirements.md#5.5), [6.2](requirements.md#6.2)

- [x] 7. Red: Write deferred mutation service regression tests <!-- id:ztq9ldw -->
  - Add dedicated TaskService/MilestoneService prepare/apply tests and ProjectService/milestone-delete deferred-save tests. Suspend allocation before reference deletion/change, competing-name creation or cancellation; assert revalidation before insertion. Preserve existing UI/intent facades and atomic status/comment behavior. Use separate test files; do not edit stream 1 encoders/fixtures.
  - Blocked-by: ztq9ldr (Green: Implement the receipt model and passing persistence probe)
  - Stream: 2
  - Requirements: [3.3](requirements.md#3.3), [4.4](requirements.md#4.4), [5.4](requirements.md#5.4), [6.2](requirements.md#6.2)

- [x] 8. Green: Split creation preparation from synchronous application <!-- id:ztq9ldx -->
  - Modify TaskService.swift/MilestoneService.swift to allocate without inserting
  - then revalidate pinned UUIDs and apply synchronously. Add ProjectService deferred creation and MilestoneService deferred deletion
  - preserving current saving defaults. Reuse status/comment and task-update deferred application; audit design-listed callers and cancellation/reference invariants. Verification: make test-mcp-write-services MCP_PROBE_SWIFT_FLAGS=-disable-sandbox passed production-service preparation/no-insert
  - live milestone status/name checks
  - deferred project/delete/status-comment save
  - suspended allocation reassignment/cancellation and peer project deletion. make lint passed. Logs: /tmp/t2380-services-green.log and /tmp/t2380-services-lint.log. Dedicated Swift Testing suite added; full app runner remains blocked by environment permissions.
  - Blocked-by: ztq9ldw (Red: Write deferred mutation service regression tests)
  - Stream: 2
  - Requirements: [3.3](requirements.md#3.3), [4.4](requirements.md#4.4), [5.4](requirements.md#5.4), [6.2](requirements.md#6.2)

- [x] 9. Red: Write coordinator replay, conflict and uncertainty tests <!-- id:ztq9ldy -->
  - Add MCPWriteCoordinatorTests for all command families, concurrent keys, restart replay after edit/delete, stale-precondition replay, normalized records and deletion preimages. Inject acceptance/serialization/save/recovery faults; cover baseline edit preservation, guard-only/inconsistent state, null acceptance, cancellation and uncertain requests never executing again.
  - Blocked-by: ztq9ldv (Green: Implement local guards and scoped receipt storage), ztq9ldx (Green: Split creation preparation from synchronous application)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [6.2](requirements.md#6.2)

- [x] 10. Green: Implement coordinated acceptance, mutation and recovery <!-- id:ztq9ldz -->
  - Create MCPWriteCoordinator.swift and MCPWriteCommand.swift and MCPWriteOutcome.swift under MCP/Writes. Bind keys durably before preparation; save baselines without rollback on failure; compare live state and apply/encode/commit without suspension. Manage autosave and remove fresh inserts before rollback; inspect durable receipts on thrown saves and classify recovery with injected clock/storage seams. Verification: Swift6 actual-production standalone coordinator checks passed all eight command families plus replay/restart/deleted-target/conflict/uncertainty plus active matching/mismatched keys plus commit-before/after-throw and serialization/recovery/acceptance/baseline faults plus fixed expiry/null acceptance/busy scope. Log: /tmp/t2380-contract-green.log. Dedicated app Swift Testing suites remain unexecuted due environment limitations.
  - Blocked-by: ztq9ldy (Red: Write coordinator replay, conflict and uncertainty tests)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [6.2](requirements.md#6.2)

- [x] 11. Red: Write protected MCP schema and handler contract tests <!-- id:ztq9le0 -->
  - Extend MCPTestHelpers with fresh-key/read-revision helpers. Parameterize all eight protected tools and four preconditions; test malformed/unknown inputs reserve nothing, full reads expose revisions, saved comments/records share projections, and protocol/domain errors stay distinct. Define executable read/write/replay/conflict examples.
  - Blocked-by: ztq9ldz (Green: Implement coordinated acceptance, mutation and recovery)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [4.1](requirements.md#4.1), [4.3](requirements.md#4.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)

- [x] 12. Green: Route protected tools through the coordinator <!-- id:ztq9le1 -->
  - Modify MCPToolHandler.swift and MCPToolDefinitions.swift for required safety inputs and typed commands and snapshot projections and JSON outcome/error envelopes. Preserve shared intent serializers and maintenance paths. Publish scope/retention/revision limits and examples in tool descriptions and docs/mcp-write-contract.md. Verification: production coordinator/schema Swift6 executable passed; make lint and check-mcp-write-handler-syntax passed. Semantic handler typecheck could not import cached NIOCore built with Swift6.3.3 into current Swift6.4. App injection and legacy fixture migration remain planned in tasks13–14; app test execution remains pending.
  - Blocked-by: ztq9le0 (Red: Write protected MCP schema and handler contract tests)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [4.1](requirements.md#4.1), [4.3](requirements.md#4.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)

- [x] 13. Red: Write lifecycle and transport recovery integration tests <!-- id:ztq9le2 -->
  - Extend MCPHTTPTestHelpers and add actual-dependency lifecycle/transport tests: protected notifications, ordered non-atomic batches, listener restart/disconnect during allocation, lock lifetime and fallback rejection. Verify UI/service/intent/maintenance and separately saved imported-state revisions without claiming global sync ordering. Update legacy calls with keys/revisions while preserving their original assertions.
  - Blocked-by: ztq9le1 (Green: Route protected tools through the coordinator)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [2.4](requirements.md#2.4), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [5.4](requirements.md#5.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)

- [x] 14. Green: Wire app lifecycle and complete transport regressions <!-- id:ztq9le3 -->
  - Inject one coordinator from TransitApp; integrate lock/guard startup
  - cleanup and shutdown with MCP ownership. Complete lifecycle/transport behavior and migrate fixtures without weakening regression checks. Run focused checks then make lint and make test-quick
  - retaining full logs; report unrelated inherited failures without expanding scope. Production schema publication is the separate release prerequisite. Verification: actual-production coordinator probe passed all eight tools plus mixed metadata normalization and retained original-payload replay
  - concurrency
  - restart
  - ambiguity
  - expiry and injected faults. make lint and Makefile app/MCP syntax checks passed. Notification/batch/active-write listener restart/disconnect/fallback/imported-state app suites authored and legacy calls migrated explicitly; full app execution remains unverified because the earlier make test-quick/Xcode fallback attempts were blocked by runner permissions/dependency environment. Logs: /tmp/t2380-lifecycle-coordinator.log
  - /tmp/t2380-lifecycle-lint.log
  - /tmp/t2380-lifecycle-syntax.log. Git index writes remain denied.
  - Blocked-by: ztq9le2 (Red: Write lifecycle and transport recovery integration tests)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2), [2.4](requirements.md#2.4), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [5.4](requirements.md#5.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)

- [x] 15. Red: Reproduce phase review numeric precision and missed caller regressions <!-- id:ztq9le4 -->
  - Add adjacent-double and finite exponent-extreme cases to canonicalization/foundation and coordinator metadata replay probes. Audit the reviewed non-MCP-named regression suites for safety fields and structured records; preserve malformed-input coverage and original domain/storage paths.
  - Blocked-by: ztq9le3 (Green: Wire app lifecycle and complete transport regressions)
  - Stream: 1
  - Requirements: [2.3](requirements.md#2.3), [6.2](requirements.md#6.2)

- [x] 16. Green: Fix lossless numbers and complete regression migrations <!-- id:ztq9le5 -->
  - Fix lossless numeric identity and all missed protected callers
  - including full MCP versus Intent domain parity. Numeric red/green and migrated caller evidence remains in /tmp/t2380-review-fix-green.log. Focused re-review correction: assert raw MCP description null/empty/string and metadata empty/nonempty against the task
  - then apply only the Intent omission policy; display/project IDs
  - project names and milestone membership remain compared with presence intact. Added provisional orphan parity case. Executed focused temporary Makefile probe against actual production MCP/Intent serializers and the extracted test projection: all 36 description/metadata/project/display-ID/milestone combinations passed (/tmp/t2380-parity-probe.log; reproducible files /tmp/t2380-parity-probe.swift and /tmp/t2380-parity-probe.mk). make lint
  - app/all-test syntax check and git diff --check passed. Full app parity suite remains unexecuted due the documented environment block; no Git commit created.
  - Blocked-by: ztq9le4 (Red: Reproduce phase review numeric precision and missed caller regressions)
  - Stream: 1
  - Requirements: [2.3](requirements.md#2.3), [6.2](requirements.md#6.2)

- [x] 17. Red: Capture full application compilation and contract regressions <!-- id:ztq9le6 -->
  - Use the app gate evidence: missing SwiftData import and a non-Sendable test task return were corrected; 1,837 of 1,853 tests passed with 16 validation/normalization/response-fixture failures. Preserve original domain assertions while separating intentional required-key/full-write-record changes. Full failure details: /private/tmp/t2380-test-summary.json.
  - Blocked-by: ztq9le5 (Green: Fix lossless numbers and complete regression migrations)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [4.1](requirements.md#4.1), [5.1](requirements.md#5.1), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [6.2](requirements.md#6.2)

- [x] 18. Green: Resolve runtime contract regressions and pass application checks <!-- id:ztq9le7 -->
  - Restore project-ID precedence
  - detailed milestone lookup errors
  - trimmed milestone descriptions and summary query shape where unchanged by scope. Migrate required-key schemas
  - full write-record null/empty assertions
  - strict unknown-field rejection
  - HTTP fixture safety and coordinator-owned save-failure injection. Parent-owned runtime verification passed: focused affected suites 115/115; full macOS application gate 1853/1853. Follow-up review found no material findings. Lint
  - syntax and diff checks passed before runtime verification. Parent owns the separate still-running combined iOS unit/UI gate and final phase documentation/commits; no additional tests or staging performed by this worker.
  - Blocked-by: ztq9le6 (Red: Capture full application compilation and contract regressions)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [4.1](requirements.md#4.1), [5.1](requirements.md#5.1), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [6.2](requirements.md#6.2)
