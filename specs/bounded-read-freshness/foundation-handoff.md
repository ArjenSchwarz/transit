# T-63 fixture foundation handoff

Tasks 2/3/6/7/8/9 are verified. The publication registry and ordinary retention are implemented and locally tested. T2382 may consume this shared API after parent review; actual cross-ticket routing acceptance remains tasks 13/16.

## Verified evidence

`make test-quick TEST_TARGETS='TransitTests/MCPReadCaptureBuilderTests TransitTests/MCPReadCoordinatorTests'` passed 17 tests: nine capture and eight coordinator cases. `make lint` passed with zero violations. RED checkpoints reproduced missing capture/coordinator/batch seams and duplicate-UUID attribution before their corrections.

The preserved result is `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/foundation/expanded.xcresult`; build/test, lint, RED logs and extracted timing lines are in that same directory. These files live outside Git and survive stream-worktree cleanup.

| Measurement | Observed |
| --- | --- |
| Hummingbird router and encoded body while MainActor blocks six seconds | 4.850738667 seconds |
| Large batch, admission through encoded selection (fallback preparation included) | 4.850275917 seconds |
| Large batch, router through encoded body | 4.857904584 seconds |
| Large request / response | 964,637 / 962,693 bytes |
| Large batch results | 8 timeout, 24 busy, 48 fixed invalid, 16 omitted notifications |

The batch harness obeys the actual Hummingbird 1 MiB body collection ceiling. It uses fixture response records, not final MCP protocol dispatch. It measures encoded transport availability, not network delivery. Scheduling evidence is empirical. Production MCPServer/handler wiring and mixed-write acceptance remain later tasks.

Capture fixtures prove saved-only fresh contexts, authoritative comment-covered r1 while output comment bodies are omitted, physical relationship identity despite duplicate UUIDs, multi-entity save rejection, empty versus purged history, import-generation invalidation, foreign milestone/orphan identity closure with unchanged declared scope, and required comment-fetch failure without empty success.

Deadline fixtures prove eight lingering physical permits/ninth busy across restart, whole-array fallback despite blocked final assembly with one retained permit, expired undispatched cleanup, 120 seeded terminal races, and forced stop/start or cutoff between admission and full-fallback readiness.

## Capture interfaces and live limitations

`MCPReadCaptureBuilder` takes the owning ModelContainer, explicit fence mode, synchronous generation closure, metadata closure `(Date, MCPReadCaptureBoundary) -> ReadCaptureMetadata`, and test injection seams. `MCPReadCaptureBoundary` contains `historyStoreIdentifier`, `generation`, and `stablePersistentHistory`. It is local fence evidence only; it cannot prove a particular CloudKit event became visible.

The metadata callback is the read-only observation hook for a signed app that owns the configured container: capture emits the boundary without saving, rolling back, publishing retention, triggering refresh, or making synthetic writes. No invocation against the signed production store was available in this execution. All disk fixtures disable CloudKit. Therefore no positive live import/history correlation is claimed. The approved production fallback is nil import applicability proof, unknown/null freshness, and unavailable refresh. Unavailable, purged, changed or incomparable local history fails closed as incoherent_capture.

Full portfolio DTOs retain complete identity closure, including foreign milestones and orphan comments; `captureScope.projects` alone controls selected totals/query scope. Canonical r1 covers comments by authoritative UUID semantics; task `commentKeys` use actual physical task ownership. Requested comment-body JSON remains optional.

## Coordinator assumptions for task 9

Coordinator, timer, admission/generation and publication terminal selection share `MCPReadPublicationDomain.withLock`. A prepared success validates every candidate before any commit and chooses response bytes atomically with swaps. Same-store children must already be coalesced; duplicate store candidates select preencoded busy errors. Physical entry removal happens only in worker finalizers.

Batch admission reserves at most eight compact entries from one generation atomically. Bulk fixed/fallback construction stays outside the domain. The assembly entry remains pending until its complete fallback is ready; stop marks it invalidated without selecting individual bytes. Original admittedAt never resets. Workers dispatch only after readiness. One completed-capture permit remains held through final assembly. No child result publishes before the selected full array.

Task 9 must extend the common lock domain without a second store lock. Displaced/discarded large indices and reservations must remain alive through unlock, including commitLocked/discardLocked paths.

## Agreed publication contract to implement

The following field/signature shape is coordinated with parent/T2382 and implemented locally, with acceptance evidence below.

- Immutable `MCPPublicationRoot`: id:String, deadline:ContinuousClock.Instant, encodedByteCount:Int, tokens:Set<String>.
- Precomputed validated `MCPPublicationIndexDescriptor`: roots:[String:MCPPublicationRoot], entryCount:Int, encodedByteCount:Int, tokens:Set<String>.
- `MCPPublicationIndex`: descriptor:MCPPublicationIndexDescriptor.
- `MCPPublicationStoreSnapshot`: version:UInt64, tokenVersion:UInt64, index:any MCPPublicationIndex, allocatedTokenSets:[Set<String>].
- Domain register(storeID,index,maxEntries,maxBytes), snapshot(for:), reserve(storeID,operationID,expectedVersion,expectedTokenVersion,index,chargeEntries,chargeBytes,newTokens,deadline), transfer(children,aggregateIndex,operationID), and retire(storeID,expectedVersion,replacementIndex).

Descriptors, counts, token unions/collision indices and net-delta validation are built outside the domain. The short gate rechecks pinned store/token versions, at most eight root expiries, scalar capacity and ownership, then swaps prepared references. Charges must be exact nonnegative net additions; published plus pending remains bounded. Never mutate/copy a large global token Set under the gate: use version-pinned immutable token-set/index references. Register once per store; no live eviction.

Existing root expiry never extends: append keeps exactly the original deadline. Transfer accepts only live same-store/same-base children with unique operation ownership, moves their exact summed charges once without gap/double count, and changes nothing on failure. It pins a fresh aggregate tokenVersion; each child's original tokenVersion need not remain current because sibling reservations advance it. Test sibling aggregation with intervening allocations and unrelated-store token races. Final validation rechecks store/base version, root existence and expiry. CAS conflicts choose preencoded READ_BUSY, never overwrite another index.

Ordinary retention keeps eight snapshots, 16 MiB encoded bytes, 300 seconds and frozen metadata. Ordinary cursor UUIDv4 versus reusable UUIDv8 routing remains recognizable after expiry, with atomic allocation/collision checks. Preserve existing selector/input/cursor error precedence. T2382 owns its separate retained store; do not implement it here. Tests must cover creates/appends/create+append coalescing, charged ownership transfer and exactly-once rollback, stale CAS, collisions, expiry, all-candidate validation and no success referencing unpublished IDs.

## Task 9 verified API and evidence

The implemented registry lives in `MCPReadPublicationDomain`, its preparation extension, and `MCPPublicationIndex.swift`. Register one immutable index per store. Capture `snapshot(for:)`, build descriptor/token unions and exact nonnegative net additions outside the lock, and call `reserve` with both captured `expectedVersion` and global `expectedTokenVersion`. `PublicationRejection` is an Error (`busy`, `expired`, `capacity`). `accounting(for:)` exposes numerical visible/pending entry and encoded-byte totals for acceptance fixtures.

`transfer([MCPPublicationReservation], aggregateIndex:operationID:)` pins a fresh global token version. It accepts only same-store/same-base uniquely owned live children, validates the aggregate's per-root bytes/tokens and exact original deadlines, transfers summed charges without a gap, and leaves children with no cleanup ownership. Releasing transferred children is idempotent. Commit advances the store index version once; stale candidates cannot overwrite the index. Explicit lifecycle retirement is separate from expiry purge; preparation never evicts live roots.

All descriptor getters, set unions, descriptor/root validation and index copies run outside the lock. Final gates read cached scalar/descriptor values and at most eight root deadlines. Production time comes directly from ContinuousClock; deterministic tests use a scalar `testingInstant` seam. `withLockRetainingRetirement` lets the coordinator resume selected response bytes before draining large displaced/discarded values outside the gate. The physical permit remains owned through this cleanup.

Ordinary `MCPTaskQuerySnapshotStore` implements the participant protocol and shares the injected domain. `prepare(pages:cursors:deadline:operationID:metadataBytes:policy:)` returns an optional private reservation (one page needs no retention). `prepareAggregate` combines ordinary creates; `retainedPage(for:)` returns immutable text/metadata bytes/policy, while the existing `page(for:)` compatibility wrapper returns text. Default retention is eight roots, 16 MiB encoded bytes and the caller's original 300-second capture deadline. Metadata bytes count in the logical encoded-byte charge. `MCPCursorFamily.classify` recognizes ordinary UUIDv4 and reusable UUIDv8 without consulting retained entries, including after expiry. No T2382 retention/helper module was required or edited.

Actual macOS app verification: `make test-quick TEST_TARGETS='TransitTests/MCPReadPublicationDomainTests TransitTests/MCPTaskQuerySnapshotStoreTests TransitTests/MCPReadCaptureBuilderTests TransitTests/MCPReadCoordinatorTests'` passed 34 cases (11 publication, five ordinary retention, ten capture, eight coordinator). These include two-create selected wholebatch/no early publication, two-appends/create+append, fresh sibling token pinning and unrelated-store allocation conflicts, exact capacity/rollback counters, stale CAS, root shortening/extension rejection, expiry, reentrant descriptor getters, 16 MiB blocked destruction during commit/discard/retirement, response selection before cleanup, 24 real-reservation terminal races, and validate-all before any multi-store commit. The parent-requested canonical serialization-category repair has a RED runtime failure and GREEN test; required comment fetch remains storageFailure and history fencing remains incoherentCapture.

Evidence is preserved outside Git under `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/publication/`: `red.log`, `capture-red.log`, `verified-green.log`, `lint.log` and `verified.xcresult`. No upstream push, merge or deployment occurred. Tasks 10–16 and real cross-ticket integration are outstanding; this foundation does not claim final handler/server wiring or live CloudKit applicability proof.

## Scoped provider correction and capture cost follow-up

A compiled runtime RED (`MCPReadCaptureScopeTests.scopedCaptureKeepsCanonicalSelectedBodiesAndMinimalForeignIdentity`) reproduced copying unrelated task descriptions, metadata and canonical full records into a scoped portfolio. The provider now keeps full authoritative r1 records only for tasks in the declared physical project scope. Unrelated task endpoints remain identity closure with no description, metadata or canonical/output body. Canonical comments remain grouped by domain UUID, including duplicate-UUID owners outside scope; physical ownership keys remain independent. Required scoped orphan diagnostic evidence and cross-project milestone endpoints are preserved.

Capture-local physical-key caching and preindexed UUID/physical comment ownership replace per-task whole-comment scans and repeated physical-identifier encoding. The authoritative MCPRecordSnapshot r1 routine remains unchanged, including its comment ordering and hashing. History/import fencing and reentrancy rejection remain in place.

The first GREEN run passed the new scope/volume cases but failed the existing scoped orphan-evidence case after over-filtering orphan comments. That filtering was corrected. The subsequent actual macOS app run passed all 12 provider/capture cases; final lint passed. Evidence is retained outside Git at `../t63-review-evidence/provider/`, including RED, first GREEN and clean GREEN xcresults/logs and extracted timing output.

The volume fixture contains 2,375 tasks and 2,376 comments. Timing separates setup, physical saved capture and JSONEncoder encoding of `[Data?]` full-record bytes. This adapter is not T2382's full frozen-evidence envelope; these totals must not be directly compared with its earlier 83.393-second capture-plus-envelope measurement. This is provider evidence, not final production routing/deadline acceptance.

Clean GREEN measured setup 2.584662958 seconds, physical capture 3.287930667 seconds, and frozen record-byte encoding 0.007581875 seconds for 1,332,730 encoded bytes. The physical worker completed synchronously before the test finished. No positive CloudKit applicability/visibility evidence was invented by this optimization.


## Tasks 10–11 prepared saved-read handoff

`MCPToolHandler.prepareCoveredRead(MCPReadToolRequest, operation: MCPReadOperation)` is the async prepared-read entry. `MCPReadService.prepare(tool:arguments:operation:)` captures saved immutable DTOs, projects task single/batch/list and project/milestone values, freezes additive outer metadata, and returns private ordinary cursor reservations. Task 13 must route admitted production reads here and provide the final fully encoded transport result to the common terminal/publication gate. The old direct dispatch remains the explicit pre-integration baseline; this component checkpoint does not claim production deadline/routing acceptance.

`MCPPreparedToolRead` contains logical result convenience, authoritative `encodedToolResult` (no RPC ID), original `frozenMetadataBytes`, and private `publications`. Its encoding embeds the complete original metadata JSON bytes verbatim. Later modern transport must consume the frozen fragment rather than decode/reencode the convenience value. `attaching` does not throw after allocating reservations. Ordinary retained pages preserve original metadata, policy, payload and original capture deadline. Cursor replay performs no capture/import wait; omitted or matching policy succeeds, malformed policy is checked before lookup, and a typed conflict is checked after valid lookup.

`MCPReadOperation.remainingBudget()` uses the same publication-domain gate and original admission deadline, returning zero for expired/invalidated/selected operations. Refresh observation windows begin before the decision snapshot and remain open through capture, projection, metadata freezing and page preparation. Capture-time observation evidence determines final refresh outcome; production applicability/visibility proof remains nil, so active production freshness is unknown/null and refresh unavailable, while inactive reads are not_requested. Positive observation/policy behavior is covered by the separately verified import component suites; this service run establishes the supported nil-proof production fallback and frozen replay, not signed CloudKit visibility.

The capture request adds narrowly typed synchronous MainActor project/milestone validation hooks. Minimal identity DTOs preserve project resolution, scalar validation, milestone lookup and dependent task-fetch precedence inside one capture fence. `projectCatalog` captures task/milestone values without comments; ordinary milestone lists need no task fetch, while detailed milestone and task-filter paths use the milestone hook before dependent task capture. Ordinary UUID selector semantics remain unchanged despite physical closure attribution.

`MCPReadCaptureValidation.validateReusableCapture(_:)` validates complete typed scope, unique physical identities, required relationship/comment-owner closure, and full canonical records only for physically selected tasks. Minimal foreign task identity and orphan comment evidence remain allowed. `requireScope(_:projectKeys:)` accepts typed physical project keys and returns SNAPSHOT_INCOMPATIBLE outside declared scope. It does not narrow identity closure or implement T2382 public query parsing/filtering. T2382 continues to own reusable query dispatch and retention modules.

RED was an actual baseline compile failure for the intentionally absent new APIs, with zero runtime cases; the independent scoped provider regression has its separate compiled runtime RED. Source-only reset/restoration used enumerated SHA-pinned backups and preserved the corrected provider commit. The first GREEN failed compilation because a helper with a private nested parameter type needed explicit private access; that narrow repair was followed by a passing retry.

Actual command: `make test-quick TEST_TARGETS='TransitTests/MCPReadProjectionTests TransitTests/MCPReadServiceTests TransitTests/MCPReadCaptureValidationTests TransitTests/MCPReadCaptureBuilderTests TransitTests/MCPTaskQueryRequestTests'`. xcresult reports Passed, top-level passedTests/totalTestCount 28, device passedTests 32, zero failures/skips, and three parameterized tests with seven runs. The log lists 25 methods; the device count includes parameter executions. Cases cover saved summary/full canonical parity, duplicate UUID outcomes, frozen metadata/policy/cursor retry, machine capture failure categories, project/scalar/milestone precedence with injected fetch failures, valid empty inactive reads, retained identity/typed scope and missing canonical/comment evidence, plus directly affected capture/request regressions. Strict lint passed with zero violations in 425 files.

Evidence is retained outside Git at `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/projection/`: red.log, first-green-compile.log, green.log, lint.log, summary.json and green.xcresult. No further app jobs run after the exclusive slot was released. Tasks 12 onward remain pending. Modern source/presentation fragments, full final RPC encoding and cross-ticket server/lifecycle binding remain coordinated later integration work; no write coordinator, modern wire, push, merge or deployment was changed here.


## Adjacent tasks 10–11 compatibility and selection repair

Parent review validated four compatibility/selection defects at 0ff9876. The task read capture/storage/serialization error code is now the established QUERY_FAILED; project/milestone preparation keeps READ_FAILED behavior and failure metadata categories are unchanged. A well-typed conflicting policy after valid cursor lookup returns INVALID_INPUT per requirement 5.4. Conclusively empty selected reads no longer require unrelated comments; whole and scoped completePortfolio still require the orphan/comment diagnostic domain, even with no tasks.

Additive scalar inputs `ReadTaskSelectionValue` and `ReadMilestoneSelectionValue` plus optional synchronous MainActor `selectTaskBodies`/`selectMilestoneBodies` hooks select body keys inside the saved fence before comment/canonical serialization. They carry no models, dates, metadata or canonical records across the hook. Shared pure selection uses raw status/type, effective priority and ordinary UUID/global duplicate-ID semantics. Nonselected records remain identity closure. Filtered or unrequested corrupt task/milestone canonical dates cannot poison an otherwise valid result; selected corrupt records still return serialization_failure. Ordinary task/catalog milestone identity and summary paths do not serialize unnecessary milestone canonical dates.

CompletePortfolio rejects either public narrowing hook. Scoped portfolio automatically canonicalizes milestones within its declared physical project scope; foreign milestone endpoint closure retains physical relationships, UUID/display ID/name, raw/effective status and timestamps, with exactly minimal milestoneId/name selectedRecordJSON. T2382 explicitly confirmed no diagnostic/reconciliation consumer needs full foreign milestone JSON. Whole portfolio still canonicalizes all milestones. The foreign bad-date fixture verifies preserved selected-task authoritative r1 and physical closure, generic validation acceptance, and whole-portfolio failure for the required bad canonical record.

Runtime RED compiled and ran against HEAD22abd9d baseline sources, preserving all committed fixtures. xcresult reports Failed: 13 top-level entries, seven passed/six failed; device counts 11 passed/13 failed; seven parameterized tests with 18 runs. Failure entries reproduce empty comments, policy conflict, legacy QUERY_FAILED, task canonical selection, milestone canonical selection and foreign milestone scope. No incidental compile failure was counted as behavioral RED. The five enumerated implementation source paths were restored with exact SHA verification before GREEN.

GREEN command: `make test-quick TEST_TARGETS='TransitTests/MCPReadServiceTests TransitTests/MCPReadProjectionTests TransitTests/MCPReadCaptureBuilderTests TransitTests/MCPReadCaptureScopeTests TransitTests/MCPReadCaptureValidationTests TransitTests/MCPTaskQueryRequestTests'`. It passed: 35 top-level tests, 46 device executions, zero failures/skips, seven parameterized tests with 18 runs. Strict lint passed with zero violations in 426 files. Parent-coordinated read-only source review confirmed the four findings repaired and reported no additional issue in this repair. Production routing/deadline integration remains task 13; positive live CloudKit visibility remains unclaimed.

Evidence and source-only patch are retained outside Git at `/Users/arjen/Documents/Codex/2026-10-03/task/t63-review-evidence/projection-compatibility/`: red.log/red.xcresult/red-summary.json/red-tests.json, green.log/green.xcresult/green-summary.json, lint.log, prepared-source/sha256.json, and repair-source.patch. The exclusive app slot was released after the job and capture workers completed; no app job runs after release. A separate preexisting Transit process in another checkout was observed and left untouched. No modern wire, write coordinator, push, merge or deployment was changed. Stop before task 12 remains in effect.
