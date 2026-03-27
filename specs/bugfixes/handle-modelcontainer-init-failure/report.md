# Bugfix Report: Handle ModelContainer Init Failure

**Date:** 2026-03-27
**Status:** Fixed

## Description of the Issue

`TransitApp.init()` used `try!` to create the SwiftData `ModelContainer`. If the underlying store was corrupted, the CloudKit configuration was invalid, or a schema migration failed, the app would crash at launch with no opportunity for recovery.

**Reproduction steps:**
1. Corrupt the app's SwiftData store on disk (or misconfigure CloudKit)
2. Launch Transit
3. App crashes immediately during initialization

**Impact:** Complete app unavailability. Users cannot access the app at all when the store is in a bad state, even though the data on disk may still be recoverable after a restart or OS update.

## Investigation Summary

The issue is straightforward: a `try!` force-unwrap on a failable initializer in the critical launch path.

- **Symptoms examined:** Force crash on `ModelContainer` init failure
- **Code inspected:** `TransitApp.swift` init, `SyncManager.makeModelConfiguration`, `ContainerFactory` (new)
- **Hypotheses tested:** Single root cause — no alternative explanations needed

## Discovered Root Cause

Line 57 of `TransitApp.swift` used `try!` for `ModelContainer` initialization, converting any error into a fatal crash.

**Defect type:** Missing error handling

**Why it occurred:** During initial development, `try!` was used as a quick path assuming the container would always initialize successfully. This is generally true for in-memory and default configurations, but persistent stores with CloudKit can fail for reasons outside the app's control.

**Contributing factors:** SwiftData's `ModelContainer` init can fail due to store corruption, CloudKit misconfiguration, disk space issues, or incompatible schema migrations — none of which are preventable by the app.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Services/ContainerFactory.swift` (new) - Extracted container creation into a testable factory that catches init failures and falls back to an in-memory container
- `Transit/Transit/TransitApp.swift:58` - Replaced `try!` with `ContainerFactory.makeContainer()` call
- `Transit/Transit/TransitApp.swift:18` - Added `containerError` property to track fallback state
- `Transit/Transit/TransitApp.swift:121` - Added `@State showContainerError` to drive the alert
- `Transit/Transit/TransitApp.swift:174-185` - Added user-facing alert explaining temporary storage mode

**Approach rationale:** Falling back to an in-memory container keeps the app functional (users can still create tasks, even if temporarily) while informing them of the issue. The persistent store remains on disk, so a restart may resolve the problem without data loss.

**Alternatives considered:**
- Show a dedicated error screen instead of the normal app — rejected because it provides no utility to the user and prevents any interaction
- Attempt to delete and recreate the store — rejected because it destroys user data

## Regression Test

**Test file:** `Transit/TransitTests/ModelContainerFallbackTests.swift`
**Test names:** `successfulCreation`, `fallbackOnFailure`, `fallbackContainerIsUsable`

**What it verifies:**
- Successful container creation returns no error
- A bad store URL triggers the fallback path and returns an error
- The fallback in-memory container is fully functional for CRUD operations

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/ContainerFactory.swift` | New file — factory with fallback logic |
| `Transit/Transit/TransitApp.swift` | Replaced `try!` with `ContainerFactory`, added error alert |
| `Transit/TransitTests/ModelContainerFallbackTests.swift` | New file — regression tests |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (`make test-quick`)
- [x] Linters/validators pass (`make lint`)
- [x] Both iOS and macOS builds succeed

**Manual verification:**
- Verified the alert message is clear and actionable

## Prevention

**Recommendations to avoid similar bugs:**
- Avoid `try!` in app initialization paths — always handle errors gracefully for operations that depend on external state (disk, network, CloudKit)
- SwiftLint's `force_try` rule is enabled but was suppressed with a disable comment; consider treating force_try violations in the app entry point as errors rather than warnings

## Related

- T-504: Handle ModelContainer init failure on launch
