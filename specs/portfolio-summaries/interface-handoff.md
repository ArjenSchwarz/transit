# Portfolio foundation handoff

The self-contained result, completion-window and task-detail types are prepared in `MCPPortfolioSummaryTypes.swift`. They contain no parser, aggregation, retention or handler behavior. `MCPPortfolioFixture.swift` fixes identities, a UTC interval and independent count expectations; it does not manufacture shared capture DTOs or revision tokens.

Task 1 consumed verified T-63 foundation `6b34e83` through local integration revision `aa1715b`. The actual capture DTOs, read policy, retained-view source and publication participant protocols are bound by portfolio-owned seams. All service/parser/store/projection/handler operations throw `MCPPortfolioScaffoldError.notImplemented`; no aggregation or retention behavior is supplied. `make test-quick TEST_TARGETS='TransitTests/MCPPortfolioInterfaceTests'` passed both fixture/interface cases; `make lint` passed with zero violations. Task 2/3 are the next foundation risk gate; aggregation/store implementation remains blocked until they pass.

## Fixture construction needed from shared types

- Two projects: populated and empty. Two milestones: open with two tasks, and empty done. Nine distinct physical task keys, each legal task status once plus an unknown raw status whose effective value is idea. Physical relationships must use the actual shared `LocalRecordKey` representation.
- The idea and unknown-status tasks are assigned to the open milestone. Seven other tasks are unassigned. The done task has completion exactly at the interval start; abandoned is exactly at the end. Total is nine, workflow five, nonterminal seven; recent done is one and abandoned zero.
- One comment on the done task supplies the latest activity. A full frozen task record must come from the authoritative T-2380 revision routine with comment-covered r1 before comment-body removal. No fabricated revision may serve as canonical-evidence verification.
- A complete captured view carries T-63 `completePortfolio`, `captureScope: .wholePortfolio` (plus a separately scoped variant), shared metadata and monotonic creation/retention times. Fixtures must preserve closure records without widening the declared physical project scope.

## Pending signature binding

Confirmed actual fields/initializers for `ReadProject`, `ReadMilestone`, `ReadTask`, `ReadCommentEvidence`, `LocalRecordKey`, `ReadCaptureMetadata` and `CapturedReadView`. The saved fixture obtains every DTO from `MCPReadCaptureBuilder`, validates physical comment ownership and compares the captured token to authoritative `MCPRecordSnapshot.task`. It retains the owning `TestModelContainer`. No replacement DTOs or fabricated revisions are used.

The pure service signature is `PortfolioSummaryService.summarize(view: CapturedReadView, window: CompletionWindow) throws -> PortfolioSummary`. Projection is `MCPPortfolioProjection.task(record: ReadTask, detail: SnapshotTaskDetail) throws -> EncodedTaskRecord`. Both remain nonfunctional seams until their later GREEN tasks.

Store, prepared-publication and handler seams bind the actual T-63 `MCPReadPublicationDomain`, `MCPPreparedPublication`, `PreparedReadResult`, typed read policy and retained-view source. The parent confirmed the entrypoints before binding. Later GREEN behavior must coalesce all selected changes per store outside the gate and validate all aggregate candidates before one swap per store. T-63 retains exclusive shared-file wiring ownership; no shared registration has been added at this checkpoint.

The interface checkpoint test `serviceAndRetentionRemainExplicitlyNonfunctional` is temporary: task 5 replaces its service not-implemented assertion with aggregation coverage, and task 7 replaces its store assertions with retention coverage. Do not leave these expectations failing the full suite after GREEN implementations land.

## Foundation risk verification

Task 2's compiling runtime RED is committed as `80cc699`: the frozen-evidence adapter throws `notImplemented`. Both real router timing baselines pass. An incidental missing SwiftData import and a method filter that ran zero cases are retained in logs but are not counted as behavioral RED.

Task 3 supplies only test adapters: the encoded fixture envelope includes every frozen full task record, canonical revision, physical task/comment relationship, projects/milestones and shared metadata. Service, projection, parser, retention and handler production methods remain nonfunctional. A synthetic mixed-call adapter waits for a real protected project write, then preserves the exact saved receipt payload; it does not establish final MCP mixed-batch dispatch, which remains task 13.

The combined app run passed all seven portfolio/interface cases and 31 of 32 selected T-63 cases (38/39 overall). The existing `MCPReadCoordinatorTests.actualRouterReturnsTimeoutWhileMainActorIsBlocked` failed its final 30ms cleanup expectation while the concurrent volume capture still occupied MainActor; its router timeout was 4.851223 seconds. The unchanged coordinator suite passed all eight cases when run alone. Record both results; there is no clean combined-suite claim.

| Portfolio experiment | Observed |
| --- | --- |
| 2,375-task / 2,376-comment fixture setup, before admission | 2.810541 seconds |
| Volume admission/router body, typed timeout with no success fields | 4.851548 seconds |
| Physical capture plus complete frozen-evidence encoding | 83.393310 seconds |
| Blocked MainActor router body, timeout and no late publication | 4.857256 seconds |
| Slow whole-batch encoding router body, timeout and no late publication | 4.853930 seconds |

All volume evidence assertions passed and the physical worker drained before test completion. The 83-second capture is material: the current implementation returns the approved timeout at this volume rather than a useful successful portfolio. A likely cost is `taskValue` scanning all comments twice per task and repeatedly JSON-encoding parent physical identifiers inside the inner ownership scan; this is a source-based hypothesis, not a completed profiler attribution. T-63 owns investigation and correction; canonical r1 semantics and saved-state fencing cannot be weakened.

During task 3 inspection, the provider's completePortfolio branch (`MCPReadCaptureBuilder.swift:144`) was found to copy `allTasks` for scoped project requests as well as portfolio requests. The approved design forbids copying all unrelated full task bodies for a scoped request. The focused portfolio-owned `scopedCaptureDoesNotExpandToUnrelatedTaskBodies` case compiled and failed at runtime: an unrelated task still carried full canonical record JSON. The case preserves required identity closure and confirms the nine selected records retain canonical revisions. Task 3 remains in progress and dependent implementation is stopped pending T-63's correction and actual regression pass. No shared source was edited.

`rune next --phase --stream 1` reported no ready tasks after task 1 completed, although `rune list` retained its completed status and the stable dependency ID matched. The parent authorized explicit `rune progress` for tasks 2 then 3 after independently verifying their satisfied dependencies; no dependent aggregation/store task was started.

Evidence lives outside Git in `../t2382-review-evidence/foundation/` relative to the worktree: `interfaces.xcresult`, `risk-red.xcresult`, `combined.xcresult`, `coordinator-isolated.xcresult`, `scoped-capture-red.xcresult`, their corresponding logs, and exported diagnostics. Final lint passed with zero violations across 428 Swift files. All owned test invocations finished and their physical workers drained; the parent can release the heavy test slot. Full production dispatch/aggregation/reconciliation acceptance remains outstanding.

## Verified provider correction and task 3 completion

The parent consumed T-63 correction `a694c27` through local cherry-pick `9b3d619`, preserving portfolio-owned files. The provider now copies full task bodies/revisions only within declared physical scope and retains unrelated minimal task identity records without full JSON, revision, description or metadata. Comment ownership/canonical indexes replace the repeated inner scans. No shared source was edited by T-2382.

The fixture adapter now encodes/counts full records only for the declared physical scope, while retaining every original task identity in its evidence envelope. The original scoped regression assertion remains intact, with additional assertions proving nine selected full records, ten retained identities, absent foreign body/revision and unchanged snapshot identity. The original scoped suite passed 1/1; the original portfolio/interface suite passed 7/7. Final lint passed with zero violations across 428 Swift files.

| Same full-envelope volume fixture after correction | Observed |
| --- | --- |
| Setup before admission | 2.704333 seconds |
| Saved capture, including queueing | 3.526669 seconds |
| Physical capture plus complete envelope encoding | 3.617544 seconds |
| Router and encoded body, complete success | 3.622145 seconds |
| Full encoded result | 6,373,596 bytes |
| Canonical full records / comment evidence | 2,375 / 2,376 |
| Blocked MainActor timeout body | 4.854159 seconds |
| Slow whole-batch encoding timeout body | 4.853895 seconds |

Saved-only/pending-edit preservation, exact canonical revision, original scoped boundaries, full evidence encoding, mixed protected-write receipt preservation, no late publication and physical-worker drain assertions all passed. The body is the same synthetic full captured-evidence envelope used before correction, not a counts-only projection. These measurements establish this fixture's foundation behavior; they are not final summary aggregation/dispatch acceptance or a hard scheduling guarantee under every load.

Task 3 is complete. The shared-provider blocker is resolved for this gate; no dependent task was started in this delegation. The generic production reusable-capture validator remains T-63-owned: verify required selected-record/comment evidence without globally rejecting diagnosable orphan/invalid links or unrelated duplicate identities, and do not narrow away the original closure. T-2382 owns later filter/options and scoped attribution logic.

Rerun commands used, sequentially in the parent-granted slot:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPPortfolioScopedCaptureTests'
make test-quick TEST_TARGETS='TransitTests/MCPPortfolioInterfaceTests TransitTests/MCPPortfolioReadFoundationTests'
```

Preserved artifacts: `provider-fix-scoped.log` / `.xcresult`, `provider-fix-portfolio.log` / `.xcresult`, `provider-fix-portfolio-results.json`, `provider-fix-diagnostics/`, and `provider-fix-verified-lint.log` in the evidence directory above. All owned physical workers drained and both test commands exited; the parent can release the heavy test slot.

## Historical draft compatibility inspection (superseded by verified foundation)

Read T-63's MCPReadCaptureTypes.swift, MCPReadMetadata.swift and MCPReadPublicationTypes.swift before its verification handoff. These files are drafts; the publication domain is explicitly an identity scaffold, not a runtime completion/capacity guarantee. Nothing was copied or bound into T-2382.

Aggregation/projection fields are present: physical record/reference keys and stored UUIDs; task/milestone raw and effective status; creation/status/completion dates; descriptions, display IDs, type/priority, metadata; full comment-stripped task JSON and authoritative revision; comment keys/evidence; declared typed capture scope; frozen capture/freshness/read metadata.

Two points were reported promptly through the parent:

- The ReadTask comment says both full JSON fields are mandatory for completePortfolio. A reusable portfolio with includeComments:false requires authoritative r1/fullRecordWithoutCommentsJSON and complete comment-key/evidence closure, but requestedCommentRecordsJSON may be nil. Body-request policy must not suppress comment-covered canonical revision/evidence capture. Comment activity evidence is required even when body output is excluded.
- Runtime publication must provide a concrete same-store grouping/coalescing hook and shared-domain reservation/lookup/retirement access. The current validate/commit/discard-only protocol cannot itself identify and coalesce multiple child updates for one store. Resolve the coordinator/store hook at the T-63 runtime task before binding; one aggregate candidate and one swap per store remain mandatory.

At that earlier draft inspection, task1 remained in progress. The verified foundation consumption and current task3 blocker are recorded above.

### Confirmed capture selection

T-63 added and parent confirmed ReadCaptureSelection.projects/.milestones/.tasks(detail: ReadTaskCaptureDetail)/.portfolio, with detail.summary/.fullRecord. ReadCaptureRequest carries selection, projectSelectors, completeness and includeComments as output preference. Portfolio requests use selection.portfolio, completeness.completePortfolio and includeComments:false; they still require complete comment-covered canonical revision/evidence. Ordinary task summary selection preserves the no-comment-fetch path unless comment output is requested. The concrete draft declaration was inspected; runtime foundation remains pending. The requestedCommentRecordsJSON nullable-body clarification and publication coalescing hooks remain open in that draft.

### Proposed publication grouping seam

Parent relayed verified draft interface commit1b34efb and proposed MCPPublicationStoreID (UUID-backed Hashable/Sendable), publicationStoreID on MCPPreparedPublication and MCPReadPublicationParticipant, and participant.prepareAggregate(selected publications, in: domain) returning one prepared publication outside the terminal lock. This is compatible with one-candidate/store publication. It is not the verified runtime foundation.

Runtime must validate participant/store identity and unique operation ownership, group only final-response selected successes, transfer reservation ownership atomically without double charge or an unreserved gap, and retain one rollback owner for every reservation after aggregate preparation throws or a later participant fails. The returned aggregate retains the same store ID. Domain lookup/reservation/retirement APIs remain pending; large displaced/discarded values must survive unlocking before last-reference release.

### Runtime domain API agreement

The proposed MCPPublicationIndex exposes precomputed entryCount, encodedByteCount and tokens. Domain register/snapshot/reserve/transfer/retire operations, with MCPPublicationStoreSnapshot versioned index and MCPDomainPreparedPublication, supply the needed reusable-store seam. The participant privately merges indexes before transfer; terminal validation covers all stores before any one-swap commit. Compatibility was acknowledged through parent with these conditions:

- Append deadline is the original retained-root expiry, never a new lifetime. Root existence, base version and lifecycle remain valid at transfer/terminal commit.
- Register once per store identity. Reservation charges are nonnegative net additions against the captured base; whole replacement bytes are not charged twice. Candidate accounting and token ownership cannot admit unreserved additions. Transfer accepts live same-store/same-base children, moves summed charge/token ownership atomically once, and leaves ownership unchanged on throw.
- Snapshot/lookup/reserve/CAS/token collision use the same domain; capacity counts visible plus pending, with no live eviction. Retirement only purges expired or lifecycle-invalidated entries. All displaced/discarded indexes survive unlock before destruction, including terminal commit/discard paths.

This is API compatibility agreement, not verified runtime evidence or permission to bypass the foundation gate.

## Exact reproduction for T-63 provider correction

Current checkpoint: T-2382 `4599cd5`, incorporating T-63 foundation `6b34e83` through local dependency merge `aa1715b`. Tasks1/2 complete; task3 blocked. These commands are reproduction instructions, not additional tests run after slot release. Use an assigned shared build slot. Target whole suites because the earlier method-only filter executed zero cases.

Scoped failure:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPPortfolioScopedCaptureTests'
```

Case: `MCPPortfolioScopedCaptureTests.scopedCaptureDoesNotExpandToUnrelatedTaskBodies` in `Transit/TransitTests/MCPPortfolioScopedCaptureTests.swift:9`. Start `MCPPortfolioSavedFixture(taskCount:9, commentOnEveryTask:false)` (defaults): two projects, two milestones, nine tasks and one canonical sample comment. Add a tenth task to the fixture's initially empty foreign project (UUID00000000-0000-4000-8000-000000000002), permanent displayID10, name `Unrelated body`, description `Must not be copied for another project's scoped capture`. Save it. Capture the populated project (UUID00000000-0000-4000-8000-000000000001) with `projectSelectors:[.id(fixture.project.id)]`, `selection:.portfolio`, `completeness:.completePortfolio`, `includeComments:false`, `fence:.actorOnlyTestFixture`. The declared physical scope, nine selected records and their canonical revisions pass; the assertion that the foreign task has no full record fails.

Offending foundation source: `Transit/Transit/MCP/Reads/MCPReadCaptureBuilder.swift:143–149`, specifically line144 selecting `allTasks` for every completePortfolio request. Keep necessary lightweight identity/relationship/comment closure, but do not serialize unrelated task descriptions/metadata/full revisions. Do not filter away ambiguity into the selected scope. Evidence: `scoped-capture-red.log`, `scoped-capture-red.xcresult`, `scoped-capture-red-results.json` under the evidence directory above.

Volume workload:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPPortfolioReadFoundationTests'
```

Case: `MCPPortfolioReadFoundationTests.actualRouterBoundsComplete2375TaskCaptureAndRevisionEncoding` in `Transit/TransitTests/MCPPortfolioReadFoundationTests.swift:33`. Exact constructor: `MCPPortfolioSavedFixture(taskCount:2_375, commentOnEveryTask:true)`. It saves two projects and two milestones, 2,375 tasks cycling all eight valid statuses plus unknown, one `Revision evidence N` comment per task plus the canonical sample comment on task6 (2,376 comments total). Tasks use deterministic UUIDs/displayIDs, `Captured description N`, metadata `["fixture":"N"]`, and the fixture's fixed completion/window dates. TestModelContainer is in-memory with CloudKit disabled; fixture context autosave is disabled and all records are saved before admission. No unsaved form state or live CloudKit store is used.

Capture request is whole portfolio (`projectSelectors:nil`, `.portfolio`, `.completePortfolio`, `includeComments:false`) through a fresh MCPReadCaptureBuilder context and real MCPReadCoordinator/MCPReadTransportAdapter/Hummingbird router. The fixture envelope encodes every frozen full task record/r1, physical ownership, project/milestone values, comment evidence and shared metadata. Timing excludes fixture setup from request admission. Setup2.810541s; encoded typed timeout/body4.851548s; physical capture+encoding83.393310s. Diagnostic cleanup waits for actual completion (up to120s), then checks unfinishedCount0; it does not release permits early or widen the five-second response limit. Evidence: `combined.xcresult`, combined log and exported diagnostics.

Source inspection for the cost: `MCPReadCaptureBuilder.swift:233–239` scans all comments once for UUID-covered canonical comments and again for physical ownership per task, encoding each owner's PersistentIdentifier during that inner scan. At 2,375 tasks/2,376 comments, the ownership loop visits roughly5.64million pairs. Index canonical-UUID and physical-owner lookups once and cache capture-local physical keys while preserving authoritative r1 semantics; actual optimization verification remains T-63's work.

To reproduce the separate baseline cleanup finding, `MCPReadCoordinatorTests.actualRouterReturnsTimeoutWhileMainActorIsBlocked` failed its final30ms unfinishedCount assertion during the combined portfolio/coordinator run; the unchanged full coordinator suite alone passed8/8. Do not describe this as a response-deadline failure. The accepted production-validator split is T-63 capture/closure/physical-scope validation without public query arguments or narrowing away original closure, and T-2382 snapshot API/filter compatibility and scope-aware attribution.


## Task 6 RED preparation: reusable retention

Stream `stream/portfolio-summaries-stage2-2` starts at `ef67ff4`. Task 6 is in progress: 22 behavior assertions are drafted across `MCPReusableSnapshotStoreTests.swift` and `MCPReusableSnapshotPublicationTests.swift`, all within the `MCPReusableSnapshotStoreTests` suite. The T-63 heavy slot excludes app builds/test execution here. `make lint` passed with zero violations in 430 files; `swiftc -frontend -parse` passed syntax-only inspection. Neither establishes app compilation, actual RED, or runtime correctness. Task 7 GREEN remains blocked until runtime RED failures are established against the unchanged nonfunctional methods.

Requested serialized RED run after parent grants the slot:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPReusableSnapshotStoreTests'
```

The test contract covers eight views/no eviction; sixteen MiB charged capture plus first summary page plus continuation bytes; pending charges and idempotent rollback; append-only page charges; root/cursor expiry at the original five-minute boundary; immutable capture metadata, revisions/full bodies, original request/window and declared physical scope; one swap/version increment for two same-store creates and two same-root appends; stale CAS; lifecycle and concurrent lifecycle/expiry invalidation; reserved/published/cross-store v8 cursor collisions; selected-query scope and malformed page-pair rejection; independent admission deadline; real coordinator validation of all stores before any commit and timeout rejection of late encoded success; private encoding-abort rollback; actual retained bundle deinitialization after discard/invalidation outside the domain lock. No shared DTO/provider/registration source changes are included.

Candidate-backed signature refinement is necessary for the actual shared domain: `reserve` validates exact root IDs, root deadlines, candidate-index deltas and globally allocated tokens. Reserving anonymous byte counts cannot later transfer ownership to a differently identified root. Added nonfunctional signatures are `reserveCreate(bundle:publicationDeadline:)`, `reserveAppend(snapshotID:pages:cursors:publicationDeadline:)` and `prepare(reservation:)`; the admission deadline is separate from original retained capture expiry. `retainedView(for:now:)` supports original-request replay, and `page(for:now:)` returns `RetainedPage(root:encodedPage:)`, preserving frozen metadata/options rather than returning unassociated bytes. Typed store errors distinguish invalid snapshots, invalid cursors and incompatible captured options/scope.

Store initialization is now throwing so task 7 can register its empty immutable index with the existing shared domain without swallowing registration failures. The current initializer remains registration-free, so RED tests reach explicit operational scaffold failures. The temporary interface checkpoint callsite adds `try`; its old byte-only reservation assertion is retained solely until task 7 replaces that checkpoint and removes obsolete byte-only/prepare-bundle seams. No retention behavior is implemented.

`EncodedViewBundle.lifetimeProbe` is an optional internal Sendable reference, nil by default. Tests attach a deinitialization probe to the actual immutable bundle/index lifetime; GREEN must retain this reference with that bundle. A probe attempts domain reentry from another queue and reports whether deinit blocked under the domain lock. It is never a manually invoked callback and adds no user-visible schema/API fields. Existing shared domain retirement tests remain regression coverage; they do not replace these store-level lifetime assertions.

Rune `next specs/portfolio-summaries/tasks.md --phase --stream 2 --format json` returned no ready tasks despite completed tasks 1–3 and task 6's satisfied dependency. Parent already identified this selection anomaly; explicit `rune progress ... 6` records preparation without marking RED complete. Actual app compilation may uncover interface/test-isolation errors and must precede interpretation of behavioral failures. Missing symbols or compile errors must be corrected before accepting RED evidence.

## Integrated task 4/6 preparation checkpoint

User approval `Sentinel_eafda56391a48191a3c414fef34d1307` explicitly authorizes local implementation sub-branch merges into their ticket branches while leaving main untouched. After that approval, aggregation preparation `a449af6` and retention preparation `563dc93` were integrated into `T-2382/portfolio-summaries` by local merges `de8c4b8` and `6280dbb`. The earlier integration attempt was rejected by automatic approval review under the original no-merge wording; it made no repository change. No main/PR merge, push or deployment occurred.

Task 4 adds aggregation/activity/window tests and seeded independent reference checks in `PortfolioSummaryServiceTests.swift`, `PortfolioSummaryPropertyTests.swift` and `PortfolioSummaryTestValues.swift`. Own typed error declarations distinguish identity ambiguity/incoherent capture and invalid completion windows without implementing behavior. The aggregation and retention preparations passed read-only peer review. On the combined revision, `make lint` passed both repository guards and reported zero violations in 433 files; `git diff --check ef67ff4..HEAD` passed. Tasks 4/6 remain in progress: no app compilation or runtime RED has been claimed.

Queued serialized commands, pending the parent's shared-slot grant:

```sh
make test-quick TEST_TARGETS='TransitTests/PortfolioSummaryServiceTests TransitTests/PortfolioCompletionWindowTests'
make test-quick TEST_TARGETS='TransitTests/MCPReusableSnapshotStoreTests'
```

Read-only inspection of T-63 revision `0ff9876` identified a later handler integration alignment: its `prepareCoveredRead` returns tool-level `MCPPreparedToolRead`, carrying encoded tool results, frozen metadata bytes and staged publications. T-2382 task-1 handler stubs still return transport-level `PreparedReadResult`. Coordinate the own-handler signature adjustment through parent before task 10/12 binding; no shared interface/source or handler signature was changed at this checkpoint, and this T-63 revision was not imported.

## Tasks 4/6 runtime RED checkpoint

The parent granted one serialized heavy slot for the two queued commands above. The first aggregation attempt failed compilation before any tests ran: the retention test file used a semaphore wait from an async context and a helper signature exposed a private type. Own test-only correction `ab04455` replaced the wait with cooperative physical-completion polling and made the helper private. No production behavior was added. Preserve this failed attempt as compilation evidence; it is not RED.

On `ab04455`, the aggregation/window retry compiled and executed 54 cases (including parameterized cases), all failing against explicit `MCPPortfolioScaffoldError.notImplemented`; xcresult has zero compiler errors and zero skipped tests. Typed invalid-window/identity expectations reject that scaffold error. The subsequent retention run compiled and executed 22 cases, all failing, with zero compiler errors and zero skipped tests. Twenty-one retention cases reach operational scaffold failures or reject that scaffold in typed error assertions. `aggregateTwoCreatesUsesOneSwapAndPreservesBoth` first encounters `PublicationRejection.busy` when taking a domain snapshot because the task-1 store initializer deliberately has not registered its index; malformed-page/scope assertions also encounter that missing-registration baseline during their final accounting check. These are missing store-feature baselines, not proof that the downstream accounting, timeout, race or lifetime assertions have exercised implemented behavior.

Tasks 4/6 are now complete as RED checkpoints; GREEN tasks 5/7 are ready according to both `rune next --phase --format json` and `rune streams --available --json`. The grant's two runs are finished; no test or build job remains owned by T-2382, and the heavy slot is released. Future GREEN runtime checks require another parent-coordinated slot.

Evidence directory: `/Users/arjen/Documents/Codex/2026-10-03/task-2/t2382-review-evidence/stage2/`. Files: `aggregation-red.log` (compile failure), `aggregation-compile-failure.json` and `.xcresult`; `aggregation-red-retry.log`, `aggregation-red-results.json`, `aggregation-red.xcresult`; `retention-red.log`, `retention-red-results.json`, `retention-red.xcresult`. The modern xcresult summary export attempted an unavailable write to its TestReport cache; the successful legacy object exports supply the verified metrics and failure messages instead.

## Task 7 source implementation checkpoint

The reusable store now registers an empty immutable index with the sole shared `MCPReadPublicationDomain`, bounded to eight roots and sixteen MiB of logical encoded bytes. `RetentionReservation` owns the actual shared-domain reservation; candidate-backed create/append/prepare signatures remain, and obsolete anonymous byte-only reservation and prepare-with-bundle methods are removed. The temporary combined service/store scaffold test is removed because tasks 5/7 now implement those seams.

Each root entry owns its original encoded bundle (including the actual lifetime probe), captured values, original request/window, first summary page and continuation mapping. Create charges capture plus first page plus continuation bytes; append charges only added bytes. Published and pending tokens use the domain's global collision/CAS checks. Lookup pins an immutable index, checks original expiry and version, and returns frozen values/pages. Expiry prepares a reduced index outside the gate; lifecycle invalidation retires the old index and pending reservations through the shared domain. Retained roots never extend their original five-minute deadline or evict a live neighbor.

Same-store aggregate preparation merges new roots and append deltas outside the lock, then transfers child ownership into one shared reservation with one index swap. Sibling discards after transfer are harmless. No independent lock, mutable budget, provider change, shared DTO change or common-handler initialization edit was added. Domain retirement retains discarded/displaced candidates until after unlocking; the bundle reference is retained by the actual index, rather than a manually invoked test callback.

Store compatibility rejects selected-query/incomplete captures, non-initial roots, non-five-minute lifetimes, malformed page pairs and non-v8 continuations. It does not duplicate T-63's generic canonical/closure validator. `validateReusableCapture` from T-63 revision `0ff9876` is absent on this source base; the later agreed handler admission must call that shared validator before retention, and identity diagnostics remain the summary service's responsibility. Minimal foreign milestone JSON `{milestoneId, name}` is sufficient provided the typed identities, relationships, optional display ID, statuses and timestamps remain captured. Foreign closure cannot widen the retained scope.

Source verification: `swiftc -frontend -parse` passed; `make lint` passed both repository guards and zero violations in 434 files; `git diff --check` passed. A lightweight standalone `swiftc -typecheck -swift-version 6 -default-isolation MainActor` passed using the actual shared domain/DTO files and small request/window/cursor declarations in `/tmp`; this is not an app build or runtime test. Its first attempt could not write the default Clang cache under the sandbox; the successful rerun used `/tmp/t2382-retention-module-cache`, without escalation or changing global settings. Task 7 remains in progress until the parent grants the serialized GREEN command:

```sh
make test-quick TEST_TARGETS='TransitTests/MCPReusableSnapshotStoreTests'
```

No app build/test, simulator job, task 8 projection implementation, push, main/PR merge or deployment occurred at this checkpoint.
## Focused GREEN checkpoint and remaining retention correction

Source streams `5219c15` (aggregation/window) and `70c1209` (retention) were integrated into the dedicated ticket branch at `857b949`. Combined lint passed with zero violations in 434 files. After the parent granted an exclusive slot, the two focused commands ran sequentially on that stable revision: aggregation/window **54/54 passed**, retention **22/22 passed**, both with zero compiler errors and zero skipped tests. Task 5 is complete. Both runs finished and the slot was released; no further heavy job is authorized by that completed grant.

Read-only peer review found one remaining task-7 defect not covered by the existing 22 tests: `retainedView` and `page` check the entire store version after pinning, so an unrelated create/append can make a still-live requested root/cursor appear invalid. Task 7 remains in progress despite its existing suite passing. The store worker paused all edits during the focused runs; after slot release it is preparing a per-root immutable-identity correction plus deterministic outside-lock interleaving regression tests. Future validation requires a new coordinated slot. Do not describe this checkpoint as complete retention correctness or final integration.

Evidence directory: `/Users/arjen/Documents/Codex/2026-10-03/task-2/t2382-review-evidence/stage2-green/`; `aggregation-green.log`, `aggregation-green-results.json`, `aggregation-green.xcresult`, `retention-green.log`, `retention-green-results.json`, `retention-green.xcresult`. No T-63 repair or validator source was mixed into these focused runs.

Confirmed tool-level return for the later T-63 bridge: own helpers should return `MCPPreparedToolRead` with staged publications; T-63 encodes the outer JSON-RPC envelope using the actual request ID before `PreparedReadResult` and terminal selection. Proposed exact own helper signatures are `handlePortfolioSummary(request: MCPPortfolioSummaryRequest, view: CapturedReadView, operation: MCPReadOperation) throws -> MCPPreparedToolRead` and `handleSnapshotTaskQuery(request: MCPSnapshotTaskQueryRequest, view: CapturedReadView, operation: MCPReadOperation) throws -> MCPPreparedToolRead`. Pass the existing admitted operation to cooperative cancellation/budget checks; do not create an independent timer or reuse retention expiry as an admission deadline. These signatures await shared wiring coordination before task 10/12 delivery; the existing handler stubs have not yet been altered.
## Verified lookup correction and capture seam

Own correction `8d4e851` preserves an immutable per-root identity across direct/aggregate appends and validates the current requested root/cursor rather than the store-wide version. Deterministic tests interleave unrelated publication, same-root append, lifecycle invalidation, expiry and same-ID/token recreation after lookup pinning. Read-only peer review confirmed the earlier defect resolved. The parent granted only the focused retention rerun; it **passed 29/29** with zero compiler errors and zero skipped tests. Task 7 is complete. The run finished and the heavy slot was released. Task 8 is the next ready task in the approved DAG.

Evidence under `/Users/arjen/Documents/Codex/2026-10-03/task-2/t2382-review-evidence/stage2-green/`: `retention-lookup-green.log`, `retention-lookup-green-results.json`, `retention-lookup-green.xcresult`. No T-63 shared source was consumed for this run.

The proposed `MCPReadCapturedPreparing.prepareCapturedRead(request:policy:operation:transform:) async throws -> MCPPreparedToolRead` is compatible with initial summaries when the transform receives a Sendable `MCPPreparedReadCapture` containing the complete declared-scope view and original `frozenMetadataBytes`, plus the same admitted operation. T-63 retains and validates observation through private preparation under that original budget; no live Models escape. T-2382 owns scope-aware ambiguity, aggregation, encoding and staged retention inside the transform, using shared generic capture validation. Replay/continuation bypass live capture and reuse the original retained view and frozen metadata bytes. The root wrapper needs an own-field refinement to persist those capsule bytes before later handler delivery; the current focused store tests compare encoded typed metadata and do not yet bind this new capsule.
## Task 8 verified RED and frozen-metadata regression

Task-8 preparation `14f050a` added projection/request/reconciliation assertions plus required `RetainedView.frozenMetadataBytes`. Scope refinement `d094e03` uses the actual provider to capture nine selected canonical task records and one foreign identity-only task, asserting that both default and explicitly narrowed queries exclude foreign closure records. Read-only peer review found no further preparation gap.

The granted projection command first failed before tests because the later-writer task used a nil required project; the first fixture correction then omitted two required Project initializer arguments. Test-only fixes `857981c` and `2d4565c` now create a separate-context project with the actual complete initializer signature. Preserve both compiler-failure results as preparation evidence, not RED or production failures.

On `2d4565c`, `MCPPortfolioProjectionTests` compiled and ran **45 cases: 43 failed against explicit `notImplemented` projection/parser seams, two existing service/ordinary stored-status checks passed**. No compiler errors or skipped tests occurred. The subsequent `MCPReusableSnapshotStoreTests` regression **passed 29/29**, verifying the required frozen-metadata field, updated fixture callsites and retained byte-preservation assertion. Both commands ran sequentially and finished; the heavy slot was released. Task 8 is complete as a RED checkpoint; task 9 is ready. Actual task-query transformation, compatibility and reconciliation behavior remains unimplemented at this checkpoint.

Evidence directory `/Users/arjen/Documents/Codex/2026-10-03/task-2/t2382-review-evidence/stage3/`: `projection-red.log` and `projection-red-retry.log`, compile-failure JSON/xcresult bundles; `projection-red-retry-2.log`, `projection-red-results.json`, `projection-red.xcresult`; `retention-regression.log`, `retention-regression-results.json`, `retention-regression.xcresult`. Later production handler preparation must explicitly include original frozen-metadata bytes in its `encodedCaptureByteCount` accounting; no accounting behavior was changed during task-8 test preparation.

## Task 9 verified GREEN under isolated host

Projection/parser source `4e1bfd38dc6562d3e70178babf5e6bb51bd9e1c9` passed peer source review with no must-fix. The parent-authorized isolation component `870a4baf6bf6d2d117e1c9c3a4446fd3fc431524` was cherry-picked as `0aef5c4a5bc0c5f2ae2a6c87a65e42ee455c3b5c`, based exactly on that source. The cherry-pick changed no MCP files. No other isolation/T-63 component was merged.

The narrow sequential grant completed: standalone isolation harness passed with `sequentialInvariantPassed:true`; dedicated development-host smoke passed 1/1; fresh projection build-for-testing succeeded. Signed-host preflight verified `me.nore.ig.Transit.development`, Debug test permission, absence of CloudKit/push/App Group entitlements, explicit `TRANSIT_PERSISTENCE_MODE=unit-test`, exact fresh host path and startup isolation guard. The generated launch retains only TransitTests/MCPPortfolioProjectionTests, with parallel testing disabled.

The first projection launch was rejected by Xcode before any cases because copied `__TESTROOT__` paths resolved relative to the evidence directory. It exited 70, with owned host drained and zero terminated PIDs. Preserve that failure as runner preparation evidence. The runner correction resolves test-root/test-host placeholders to the attested absolute products/host paths and preserves known Xcode developer placeholders. Separate attempt2 artifacts preserve all original evidence; preflight rechecks the same signed build and attested launch without overwrite.

Attempt2 passed **45 cases across 22 test declarations**, zero failures, zero skips. Xcode test-without-building and result-summary verification exited zero. Physical cleanup confirms `drained:true`, no terminated PIDs. Task 9 is complete. All owned build/test jobs have finished; the heavy slot is released. Live Transit mutations and production/server launches remain paused independently of this isolated success.

Evidence is under `/Users/arjen/Documents/Codex/2026-10-03/task-2/t2382-review-evidence/isolation/`: `harness-results.json`, `smoke-preflight.json`, `smoke-results.json`, `projection-build.log`, `projection-external-build-observation.json`, `projection-build.json`, `projection-preflight-attempt2.json`, `ProjectionOnly-attempt2.xctestrun`, `projection-tests-attempt2.log`, `projection-test-summary-attempt2.json`, `projection-test-job-attempt2.json`, `projection-tests-attempt2.xcresult`. First-attempt log/job/result and `.attempt1` preflight/launch copies remain. The summary device/configuration count records 45 passed cases; its top-level 22 count is declarations.

Task 10 is now dependency-ready, but shared binding still requires parent coordination of the exact T-63 capture-validation/preparation revision and T-2383 result-fragment delivery. This checkpoint does not consume `0ff9876` or `dc85eab`, alter shared routing, complete the full phase, run broader suites, publish a review, push, merge to main or deploy. Original freshness bytes and capture identity remain required for every retained page.

## Task 10 descriptor source checkpoint

Own descriptor source is committed at `0b7305`, with peer response-availability wording correction `1150286`. It exposes `MCPPortfolioToolDefinitions.queryProjectSummaries`, `snapshotTaskQueryInitialSchema`, `reusableContinuationSchema` and `snapshotTaskQueryDescription`. Strict disjoint branches match the existing parsers; shared query_tasks must merge its cursor alternative rather than append overlapping oneOf branches. Actual shared-type Swift 6 typecheck and lint pass, without app builds, hosts or tests. Root/peer review corrections preserve exact wire field names, lowercase read failure categories and the five-second response-availability contract.

Task 10 remains in progress pending T-63 registration/dispatch/lifecycle and shared schema bounds/const/default resolution. The exact source/API handoff and remaining helper ABI needs are recorded in `t63-module-handoff.md` for the parent's T-63 relay. Preparation does not claim delivered handlers or final integration. Parent released the slot to T-2383; T-2382 will prepare own RED source without heavy execution or live writes.

## Task 11 source preparation, dependency retained

Parent-authorized preparation `c02987b` adds 15 public-handler test declarations only. Syntax and lint pass; read-only peer review found no concrete fixture/API or false-expectation defect. A standalone typecheck against the stale isolated compiled app module was blocked before source checking by `_AtomicsShims`; no app compile, host or behavioral RED occurred. Task 11 remains pending, not started/completed in Rune, while task 10 shared wiring remains in progress. Capture fault-injection cases await the exact delivered public seam, and opaque metadata-byte wire tests await the T-2383 boundary. No shared fixture or production code was altered by this preparation.

The exact initial-summary helper ABI must forward original capsule metadata bytes as well as its typed view and admitted operation; the earlier proposed view-only signature cannot itself preserve those bytes. Parent/T-63 coordination must settle a capsule or explicit-data parameter before binding. The updated `t63-module-handoff.md` documents this requirement and the verified descriptor/test source checkpoints. All owned jobs/hosts are drained; no heavy slot is held. Live write/production-launch holds remain in force. Full integration and pre-push review/Pulsar remain outstanding.

## Agreed task-10 ABI and admitted RED fixture binding

Own `166752b` implements only the exact agreed nonisolated throw-stub interfaces: summary(request,capture:optional original capsule,operation) and snapshot(request,operation) return MCPPreparedToolRead. Initial receives the capsule directly; summary replay/continuation pass nil, and all retained paths use own root bytes without live capture. It also applies the delivered shared numeric bounds, false constant and initial-only policy default to the descriptor.

Verified T-63 b500543 MCP-only preparation was imported as 8e8d855, sole schema f4e2955 as 591555f, and failure mapper 1b2e813 as 346ceda. No App/project/isolation source changed. Updated test preparation ebaa044 has 16 declarations/18 source cases and uses authoritative bounded-dispatch Data, actual producer/service failures and actual metadata categories; plain nonquery failure text is not mistaken for an encoded READ_FAILED code. Syntax/lint and peer source review pass; app compilation and runtime remain unverified. Task10 registration/reusable-store/lifecycle wiring is still outstanding, task11 stays pending, and no heavy job/slot is held. The exact updated ABI and source handoff are in t63-module-handoff.md for parent/T-63 integration.

## T-63 exact source wiring and modern transport wording

Parent-authorized common component `226db40ec2aa78290e11ca57d40b9d7ffd18d759` was inspected with its handoff, owner map and import manifest and imported as `e13fa6f`. Only its five common MCP files changed; the ten previously owned module files were not recopied. Source-component SHA-256 is `f9da28bf0aa795651dfda650907ba65f62985fffed1aa6cca27942308b3fa57c`.

The delivered wiring registers the summary descriptor, replaces the ordinary cursor branch with the shared continuation branch, classifies summaries for bounded read admission and fallback storage, and routes retained requests before ordinary task parsing. The optional injected reusable store must share the ordinary store/coordinator/read-service publication domain; the nonisolated `Result<MCPReusableSnapshotStore, Error>` retains registration failures. Listener lifecycle invalidation fails closed. Initial summaries receive the original capsule directly under admitted capture preparation; replay, reusable continuation and snapshot task queries bypass recapture. Portfolio helper bodies remain explicit `notImplemented` stubs.

Own descriptor-only `42d2d82b8596c5a0ac65887f83d25b5bc2bf3613` follows the approved latest-only modern transport: each POST accepts one JSON-RPC object, batch arrays are rejected, and `mutate_tasks` carries application-level operations within one `tools/call` under its own write/receipt contract. Separate test-oracle correction `1cccab77cf4d4f48bc3bc640e4cc980225f4c55e` requires those positive statements. T-63 can apply the descriptor-only commit after its exact module import without copying tests or losing other owned changes. This latest transport agreement supersedes historical wire-batch wording in the planning documents.

Task 10 remains in progress until its required coordinated app compilation. Task 11 remains pending: its 16 declarations/18 expanded source cases are prepared against the delivered wiring, with no runtime RED claim. No new build, host test, live MCP write, production launch, publication, push or merge is authorized by this source-only integration checkpoint. Heavy execution awaits the parent's explicit owner-permission clarification.

A separately reported T-63 dispatcher follow-up remains pending: commit-time expiry currently emits `QUERY_EXPIRED` unconditionally. Approved retained snapshot requests require `INVALID_SNAPSHOT`, and reusable cursor requests require `INVALID_CURSOR`, with rollback and no publication. T-63 owns the family-aware preencoded fallback and focused regression. The unchanged `226db40` component does not establish the current generic expiry code as approved reusable behavior; handler expectations must preserve the required family distinction.

## Pre-gate portfolio fault normalization preparation

Parent delivered T-63 expiry regression `11cf1ab` and family mapping `11007996520d82c7e98523ad954cf072751f934c` for source-only consumption. The follow-up patch SHA-256 is `543f70119688004ac7487f63d6ae94ea23667fc082067eafdf27719a58d073c3`; original wiring and prior execution evidence remain unchanged. Its six parameterized regression cases cover actual shared stores, gate rollback, absent publication/metadata and physical drain. Neither RED nor GREEN execution is established by source delivery.

Task-12 helpers must catch retention faults before they escape into the common capture-failure mapper. The required machine-error mapping is: `PublicationRejection.capacity` → `QUERY_CAPACITY_EXCEEDED`; `PublicationRejection.busy` → `READ_BUSY`; `MCPReusableSnapshotError.invalidSnapshot` → `INVALID_SNAPSHOT`; `.invalidCursor` → `INVALID_CURSOR`; `.incompatible` → `SNAPSHOT_INCOMPATIBLE`. Pre-gate `.expired` must use the request family: summary initial/replay and snapshot task initial → `INVALID_SNAPSHOT`, summary/task reusable continuation → `INVALID_CURSOR`. Each is an error result without successful freshness metadata or unpublished identifiers; no retained lookup failure permits recapture. Preserve rollback of any reservation created before a subsequent failure.

Actual capture/coherence/serialization failures retain the shared capture mapper and its real failure metadata. Required portfolio identity/scope validation keeps its structured machine errors. Raw capacity/expiry must not escape to `prepareFailure`, whose generic fallback would mislabel them as saved-storage failures. This is a reviewed implementation contract and prepared acceptance scope; both owner helper bodies remain `notImplemented` until the actual handler RED gate permits GREEN work.

Consumed common regression `11cf1ab` as `dc84b751c6035518b698f7a015617e34a83156e0` and mapping `1100799` as `deead79815b5b9271f041c35438357d7a9cee364`; only dispatcher and its new regression file changed. Own prepared acceptance `b43dc1d` adds ninth-summary capacity and four pre-gate expired retained-family cases, using actual saved empty captures/store reservation and the existing deterministic domain clock. The handler suite now has 18 declarations/23 expanded source cases. Syntax and focused lint pass; no new source was compiled or executed. Task 10 remains in progress and task 11 pending; existing baseline evidence is preserved.

Both helpers must return the prepared machine-error result for normalized retention faults, rather than throw `MCPPortfolioRequestError`: the shared snapshot preparation bridge catches `MCPSnapshotTaskQueryError`, not `MCPPortfolioRequestError`. This distinction preserves the approved error shape across both tools.

Peer fixture correction `a2ca168acf7ab8c0ad1bda889fa89db0122db8d8` permits existing expired retained charges to remain after rejection while requiring no added visible or pending publication. Expiry text derives from captured `asOf` plus the original retention duration. This avoids imposing immediate removal or a particular helper clock implementation. The 18/23 source-case count is unchanged; parsing and focused lint pass, runtime remains unverified.

## Reviewed handler RED boundary with finalisation limitation

The parent granted an exclusive isolated run at `26e090b`. Build failed before execution solely in the delivered T-63 expiry fixture's throwing `store.prepare` inside `#require`; zero cases ran. Original build log/result/job and separate compile-failure classification remain under `handler-preparation/red-26e090b.../`. Exact owner correction `7a2f4de913beaffe166aca8d705102096488ecaf` was consumed as `cd20767592639c74ced5bd1569dfbccc0d3c868b`.

A separately granted fresh build at `cd20767` passed. Preflight verified signed development host `me.nore.ig.Transit.development`, no CloudKit/push/App Group entitlements, explicit unit-test persistence and exact-path startup guard. The restricted xctestrun selected only `MCPPortfolioHandlerTests`, serially. Console evidence records all 18 declarations/23 expanded cases completed in 0.523 seconds: four passed and nineteen failed. The subsequent Xcode finalisation did not exit within 180 seconds; the guarded runner terminated its owned process group. Job status remains `failed`, exit -15, with `drained:true`, no remaining group PIDs or terminated host PIDs. Do not claim runner `observed-red`, a finalized xcresult, normal exit or full feature acceptance. No automatic rerun is needed solely to normalize teardown.

Independent source/evidence review distinguishes fifteen meaningful scaffold-path failing cases from four fixture-only failures. Valid initial/replay/snapshot/scoped/capacity/expired-family requests reached the common preparation paths backed by the explicit `notImplemented` owner helpers: summary paths produced plain generic failure text, and task snapshot/cursor paths produced QUERY_FAILED/storage_failure instead of required retained-family errors. These demonstrate the missing handler behavior. Later semantic assertions blocked by that first failure remain obligations for GREEN acceptance. The four passing declarations establish descriptor/schema advertisement and scalar/snapshot-option validation before helpers.

The ordinary compatibility case and three capture-failure category cases instead omitted required ordinary `detailLevel`, `includeComments` and `limit`, so INVALID_INPUT occurred before capture. The producer-fault loop aborted before its summary arm. The mixed cursor-family declaration additionally used an invalid ordinary warmup after its real reusable-cursor scaffold failure. These incidental expectations require narrow own-fixture correction; they do not establish a T-63 payload or metadata defect. Capture-failure metadata remains unverified by this original run and must be observed with valid requests in the next coordinated GREEN verification.

Parent explicitly authorized completing the meaningful RED boundary with this limitation and proceeding after independent review. Task 10 is complete on actual compilation/registration evidence; task 11 is complete as the reviewed missing-handler RED boundary, with incidental fixture and finalisation limits preserved. Task 12 is in progress as a delegated source implementation; no further heavy run starts without the next parent slot grant. No live mutations occurred. Original evidence and exact console line references are in `handler-preparation/red-cd20767.../reviewed-runtime-classification.json`, the test log and failed job record.

Own fixture correction `af2deed` supplies the required ordinary arguments at the four invalid callsites, preserving results/status/order/policy/metadata expectations and 18/23 source counts. Syntax and focused lint pass; corrected fixture execution remains unverified. The detailed case-by-case original console audit is retained locally as `handler-red-oracle-classification-cd207.json` and `.md`; no routine phone delivery or progress attachment is performed.

## Task 12 delegated source checkpoint

Delegated own implementation `8478b17f554e9d7e93a3dd5b76fd1396f4295d07` changes six own source files: both handlers, reusable-store seams, summary encoding, capture charging and scalar read-pin/composite declarations. Initial summaries prepare immutable pages and charge original metadata plus encoded backing evidence before reserving. Retained replies preserve their original payload and metadata without capture; atomic pins bind lookup identity and original expiry through the final gate. Page appends combine the original pin and mutation. Guards compact outside the lock to at most eight distinct roots, validate original identity/deadline and nested domain ownership, and make no charge or swap for guard-only replies. Rollback ownership is retained until publication attachment.

Swift syntax and targeted strict lint pass. Independent wire/charge review and store-race review found no remaining own-source blocker after their refinements. No compilation or runtime GREEN is claimed for this implementation; task 12 stays in progress and task 13 remains blocked. The new guard behavior also needs runtime regression coverage. No heavy slot is held.

A source-proven T-63 selector mapper follow-up is required before GREEN. Capture-builder lines 202-203 throw `MCPReadCaptureError.projectNotFound` / `.ambiguousProject` before the owner helper. Shared portfolio preparation catches only `MCPPortfolioRequestError`, then its generic service mapper classifies these as storage failure and plain summary text. The accepted `normalizedNameResolutionAndMissingSelectorsHaveExplicitOutcomes` assertions require structured `PROJECT_NOT_FOUND` / `AMBIGUOUS_PROJECT`. Add the two narrow shared catch cases using the existing `portfolioInputFailure` before the generic mapper; preserve genuine read/coherence/serialization metadata. This is independently reviewed source proof, not a selector runtime result: the original valid-name scaffold failure blocked those later assertions. Owner helpers cannot correct a fault thrown before invocation; no common file was modified here. Local `t63-selector-fault-handoff.json` preserves exact source/assertion references.

## Integrated focused GREEN readiness

The parent-delivered sole common selector mapping `eb3d9ddc556da44c964b3e6aa2dbb4c832a04de7` was inspected with `selector-mapping.patch` and consumed as `f60c43b`. It adds only four lines: the two provider selector faults return existing structured machine errors before the generic mapper. Genuine capture-failure handling is unchanged. Source review confirms the accepted selector and three capture-category cases are reachable with the corrected request fixtures; their execution is still pending.

Own unit preparation `d67c09a` adds nine standalone `MCPReusableSnapshotReadPinTests` cases: no-charge/no-swap guard, coordinator expiry rejection and physical drain, invalidation/recreation, unrelated create/append tolerance, composite rollback, pin compaction bounds, conflicting identities and domain/store rejection. These use actual stores/domain/participant gates and existing saved fixtures. Syntax, focused lint and independent source review pass; no app compile or runtime is claimed.

Focused GREEN selects exactly `TransitTests/MCPPortfolioHandlerTests`, `TransitTests/MCPReusableSnapshotStoreTests` and `TransitTests/MCPReusableSnapshotReadPinTests`. The new external `handler_green_runner.py` preserves reviewed source/isolation/signing/startup/absolute-launch/cleanup guards, uses fresh revision-specific GREEN paths and captures summary/failure details even on incidental exit 65. Only exit zero, actual fully passed cases and passing console evidence for all three suites can establish GREEN; cleanup must drain before status passes. Runner SHA-256 is `90c3c7cfb1890c8c1213efc70b0198735a5511b216537d50273b173b35a2a9d3`; fourteen offline fake checks and independent source review pass. Original GREEN/RED runners and earlier evidence remain unchanged. No runner phase has executed. Parent reports T-1734 owns the heavy slot; await the next explicit exclusive grant. Task 12 remains in progress.
