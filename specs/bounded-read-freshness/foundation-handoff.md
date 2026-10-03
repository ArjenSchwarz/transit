# T-63 fixture foundation handoff

Tasks 2/3/6/7 are verified. Task 8/9 publication/ordinary-retention work remains pending; this checkpoint does not authorize binding T2382 to an unimplemented registry.

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

The following field/signature shape is coordinated with parent/T2382; only the existing store-ID/participant/prepared interfaces are currently implemented.

- Immutable `MCPPublicationRoot`: id:String, deadline:ContinuousClock.Instant, encodedByteCount:Int, tokens:Set<String>.
- Precomputed validated `MCPPublicationIndexDescriptor`: roots:[String:MCPPublicationRoot], entryCount:Int, encodedByteCount:Int, tokens:Set<String>.
- `MCPPublicationIndex`: descriptor:MCPPublicationIndexDescriptor.
- `MCPPublicationStoreSnapshot`: version:UInt64, tokenVersion:UInt64, index:any MCPPublicationIndex, allocatedTokenSets:[Set<String>].
- Domain register(storeID,index,maxEntries,maxBytes), snapshot(for:), reserve(storeID,operationID,expectedVersion,index,chargeEntries,chargeBytes,newTokens,deadline), transfer(children,aggregateIndex,operationID), and retire(storeID,expectedVersion,replacementIndex).

Descriptors, counts, token unions/collision indices and net-delta validation are built outside the domain. The short gate rechecks pinned store/token versions, at most eight root expiries, scalar capacity and ownership, then swaps prepared references. Charges must be exact nonnegative net additions; published plus pending remains bounded. Never mutate/copy a large global token Set under the gate: use version-pinned immutable token-set/index references. Register once per store; no live eviction.

Existing root expiry never extends: append keeps the original deadline or an earlier one. Transfer accepts only live same-store/same-base children with unique operation ownership, moves their exact summed charges once without gap/double count, and changes nothing on failure. It pins a fresh aggregate tokenVersion; each child's original tokenVersion need not remain current because sibling reservations advance it. Test sibling aggregation with intervening allocations and unrelated-store token races. Final validation rechecks store/base version, root existence and expiry. CAS conflicts choose preencoded READ_BUSY, never overwrite another index.

Ordinary retention keeps eight snapshots, 16 MiB encoded bytes, 300 seconds and frozen metadata. Ordinary cursor UUIDv4 versus reusable UUIDv8 routing remains recognizable after expiry, with atomic allocation/collision checks. Preserve existing selector/input/cursor error precedence. T2382 owns its separate retained store; do not implement it here. Tests must cover creates/appends/create+append coalescing, charged ownership transfer and exactly-once rollback, stale CAS, collisions, expiry, all-candidate validation and no success referencing unpublished IDs.
