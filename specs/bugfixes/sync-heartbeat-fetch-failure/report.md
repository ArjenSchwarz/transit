# Bugfix Report: Sync Heartbeat Fetch Failure

**Date:** 2026-08-05
**Status:** Fixed

## Description of the Issue

`SyncManager.beat(context:)` treated a failed SwiftData fetch for the `SyncHeartbeat` singleton exactly like an empty result. The expression `(try? context.fetch(descriptor))?.first ?? SyncHeartbeat()` created and inserted a new record whenever the fetch threw.

**Reproduction steps:**
1. Run a heartbeat against a context whose `SyncHeartbeat` fetch throws.
2. The failed optional fetch evaluates to `nil`.
3. The fallback creates and saves a new `SyncHeartbeat`, despite the store not being readable.

**Impact:** A transient fetch failure could insert a duplicate fixed-ID singleton. CloudKit-backed SwiftData cannot use `@Attribute(.unique)`, so future heartbeat runs could update an arbitrary duplicate.

## Investigation Summary

- **Symptoms examined:** A fetch error was silently collapsed into the normal missing-record path.
- **Code inspected:** `SyncManager.beat(context:)`, `SyncHeartbeat`, timer callers, existing sync tests, and the CloudKit/SwiftData persistence constraints.
- **Hypotheses tested:** The issue occurs before the best-effort save; preserving `try? context.save()` does not prevent the duplicate insertion. A deterministic injected fetch closure confirmed that an error must be handled separately from an empty result.

## Discovered Root Cause

The heartbeat's error-handling expression combined two semantically different states: a successful empty fetch (the singleton is missing) and a failed fetch (the store is unavailable). The nil-coalescing fallback then created a model for both.

**Defect type:** Logic error / swallowed storage failure.

**Why it occurred:** `try?` erased the fetch error before the code chose whether creation was valid. The code had no branch that could skip the beat after a storage-read failure.

**Contributing factors:** The singleton's fixed string ID is not a unique attribute because CloudKit does not support SwiftData unique constraints, so an accidental insert is not rejected locally.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/SyncManager.swift` - adds an injected `HeartbeatFetcher` seam for deterministic tests; `beat(context:)` now catches fetch errors, logs the skipped heartbeat, and returns before insertion or save. A successful empty result still creates the singleton; a successful existing result still updates it. The existing timer loop and best-effort `try? context.save()` remain unchanged.
- `Transit/TransitTests/SyncManagerTests.swift` - adds missing-singleton, existing-singleton, and failure-then-recovery regression coverage using a controllable fetcher.

**Approach rationale:** Returning before mutation is fail-closed: it cannot add a duplicate when the singleton's existence is unknown, and the already-scheduled next timer iteration retries normally.

**Alternatives considered:**
- Continue treating a fetch failure as an empty result - rejected because it is the source of duplicate singleton records.
- Add a unique attribute to `SyncHeartbeat.id` - rejected because CloudKit-backed SwiftData does not support unique constraints.
- Stop the timer after an error - rejected because transient storage failures should recover on the next scheduled beat without changing timer lifecycle.

## Regression Test

**Test file:** `Transit/TransitTests/SyncManagerTests.swift`
**Test names:** `heartbeatWithMissingSingletonInsertsOneRecord`, `heartbeatWithExistingSingletonUpdatesWithoutInsertingAnotherRecord`, and `heartbeatFetchFailureInsertsNothingAndNextBeatRecovers`

**What it verifies:** A successful empty fetch creates one record, a successful existing fetch updates without adding another record, and an injected fetch failure inserts zero records before a later successful beat recovers normally.

**Run commands:** `make test-quick`; `make lint`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/SyncManager.swift` | Separates failed fetches from missing singleton results and logs skipped beats. |
| `Transit/TransitTests/SyncManagerTests.swift` | Adds deterministic singleton and recovery regression tests. |
| `CHANGELOG.md` | Records the fixed heartbeat-fetch behavior. |

## Verification

**Automated:**
- [x] Focused `SyncManagerTests` pass.
- [x] Full macOS unit suite passes (`make test-quick`).
- [x] Strict lint passes (`make lint`).

**Manual verification:** Not required; the failure path is covered deterministically through the injected fetch seam.

## Prevention

- Do not use `try?` where a fetch result controls whether a CloudKit-safe singleton may be inserted.
- Keep read failure, empty result, and successful result as distinct control-flow paths.
- Exercise error paths through an injected seam while retaining real mutation and save behavior in tests.

## Related

- Transit task T-1699: Sync heartbeat fetch failures can create duplicate singleton records.
- `How to allocate human-friendly sequential IDs in a CloudKit app` — generated knowledge note on CloudKit's lack of SwiftData unique attributes.
