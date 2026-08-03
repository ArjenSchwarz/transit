# Bugfix Report: Mutation Intents Misclassify Persistence Failures

**Date:** 2026-08-04
**Status:** Fixed
**Ticket:** T-1770

## Description of the Issue

Five JSON mutation App Intents treat a valid request that cannot be completed because SwiftData storage failed as caller-invalid input (or, for some lookup paths, as a missing record). Automation clients therefore cannot distinguish retryable storage failures from permanent request errors.

**Reproduction steps:**
1. Submit a valid create, update, or delete request to an affected intent.
2. Make the intent's save or required lookup fetch throw while the backing context remains otherwise usable.
3. Observe an `INVALID_INPUT` / not-found response rather than `INTERNAL_ERROR`.

**Impact:** Retry-capable callers can discard valid work after a transient storage or CloudKit failure, and the same domain failure has inconsistent semantics between mutation intents.

## Investigation Summary

### Phase 1: Initial overview

Expected behavior: JSON validation and typed domain errors remain their established public payloads; untyped persistence or storage errors return `INTERNAL_ERROR`. Actual behavior: `CreateMilestoneIntent`, `UpdateStatusIntent`, `UpdateMilestoneIntent`, and `DeleteMilestoneIntent` use generic catches that return input or not-found payloads. `CreateTaskIntent`'s final creation catch is already correctly mapped, but its display-ID milestone lookup can still turn a generic fetch failure into `MILESTONE_NOT_FOUND`.

### Phase 2: Systematic inspection

- `CreateTaskIntent`: creation errors are already mapped by typed `TaskService.Error` cases with an `INTERNAL_ERROR` default; its display-ID milestone lookup catches every non-`MilestoneService.Error` as not-found.
- `CreateMilestoneIntent`: typed `MilestoneService.Error` values use `IntentHelpers.mapMilestoneError`, but the generic creation catch returns `INVALID_INPUT`.
- `UpdateStatusIntent`: valid status updates catch every service failure as `INVALID_INPUT`.
- `UpdateMilestoneIntent`: its atomic `MilestoneService.save()` failure is caught as `INVALID_INPUT` after mutations have been applied; service recovery must roll them back.
- `DeleteMilestoneIntent`: deletion and untyped identifier-lookup failures are reported as input/not-found errors.
- `TaskService`: creation uses `insertOrDelete`, status updates call `safeRollback()` on any save failure.
- `MilestoneService`: creation uses `insertOrDelete`; save/update/delete use `saveOrRollback`, but it lacks a service-level injected saver and its direct lookup methods bypass the existing injected `ModelFetching` seam.
- `IntentHelpers.resolveTask` and `resolveMilestone` preserve typed not-found/duplicate/validation cases but currently collapse unexpected fetch errors into not-found.

### Phase 3: Root cause analysis

1. Why are callers told their request is invalid? Generic `catch` clauses select `invalidInput` or not-found payloads.
2. Why do generic catches receive storage errors? The services expose raw SwiftData fetch/save failures alongside typed domain errors.
3. Why are generic lookup failures not deterministic in tests? `TaskService.findBy…` and `MilestoneService.findBy…` read `modelContext` directly rather than their injectable fetchers.
4. Why cannot all milestone mutation saves be simulated through an intent? `MilestoneService` accepts a creation-only save closure and `save()` / `deleteMilestone()` use fixed context saves.
5. **Root cause:** Intent error translation conflates typed caller/domain failures with untyped infrastructure failures, and incomplete injection seams leave the distinction untested on every affected path.

**Assumptions validated:** The save helpers provide the required recovery: creates delete only the newly inserted model; updates/deletes `safeRollback()` and re-fault models. The fix must retain these helpers and change response translation/seam routing only.

## Resolution for the Issue

**Changes made:**
- Routed every untyped create/update/delete and direct identifier-lookup failure through `INTERNAL_ERROR`, with typed validation, not-found, duplicate, and domain catches retained ahead of the generic catch.
- Made `TaskService` and `MilestoneService` direct UUID/display-ID/name lookups use their injected `ModelFetching` instance.
- Added `MilestoneService.mutationSave` and a closure-based `ModelContext.saveOrRollback(save:_:)` overload, retaining `safeRollback()` for update/delete failures and `insertOrDelete` cleanup for creates.
- Added ten deterministic parity tests—one failing-fetch and one failing-save path for each affected intent—asserting a two-key `INTERNAL_ERROR` envelope and no persisted mutation.

**Approach rationale:** Reusing the established `UpdateTaskIntent` convention preserves the public error vocabulary and differentiates caller action from infrastructure state. The smallest safe change is at the existing service seam and each final error-translation boundary; rollback behavior remains in the service layer.

**Alternatives considered:**
- Convert all raw service errors into a new typed domain case — rejected because it widens the domain API while callers already have `INTERNAL_ERROR` for this exact condition.
- Leave lookup methods on `modelContext` and test only saves — rejected because generic fetch catches are part of the defect and would remain untestable.

## Regression Test

**Test file:** `Transit/TransitTests/MutationIntentStorageFailureTests.swift`

**What it verifies:** Every affected intent returns a two-key `INTERNAL_ERROR` envelope for a deterministic storage failure and does not create, update, or delete model state.

**Red run command:**
```bash
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=macOS' \
  -only-testing:TransitTests/MutationIntentStorageFailureTests
```

## Affected Files

| File | Change |
|---|---|
| `Transit/Transit/Intents/CreateTaskIntent.swift` | Correct untyped milestone lookup mapping. |
| `Transit/Transit/Intents/CreateMilestoneIntent.swift` | Map generic creation failures to `INTERNAL_ERROR`. |
| `Transit/Transit/Intents/UpdateStatusIntent.swift` | Map generic status-save failures to `INTERNAL_ERROR`. |
| `Transit/Transit/Intents/UpdateMilestoneIntent.swift` | Map generic save failures to `INTERNAL_ERROR`. |
| `Transit/Transit/Intents/DeleteMilestoneIntent.swift` | Map generic delete/lookup failures to `INTERNAL_ERROR`. |
| `Transit/Transit/Intents/IntentHelpers.swift` | Preserve typed mappings and surface unexpected shared lookup errors as internal. |
| `Transit/Transit/Extensions/ModelContext+Save.swift` | Add injected-save rollback overload that preserves `safeRollback()` recovery. |
| `Transit/Transit/Services/TaskService.swift` | Use deterministic injected fetcher for direct lookup. |
| `Transit/Transit/Services/MilestoneService.swift` | Use deterministic injected fetcher and saver for mutation paths. |
| `Transit/TransitTests/MutationIntentStorageFailureTests.swift` | Add failure-path/no-mutation parity coverage. |

## Verification

**Automated:**
- [x] Regression suite fails before the fix: all five deterministic failing-fetch cases failed.
- [x] Regression suite passes after the fix: all ten fetch/save cases pass on macOS.
- [x] Affected intent/service/save-helper suites pass on macOS, including existing typed caller-error payload coverage.
- [x] macOS unit suite passes: `make test-quick`.
- [x] Linter/ownership guard passes: `make lint`.
- [x] Production builds pass: `make build` (iOS Simulator and macOS).
- [ ] Full `make test` did not complete before the 10-minute harness cap; it built successfully, started the new suite, and independently exposed the same three unrelated UI failures below.
- [ ] Focused iOS regression run did not complete before the 10-minute harness cap during simulator build/execution.
- [ ] `make test-ui` reproduces unrelated failures in `TransitUITests.testClearAll`, `TransitUITests.testEditViewPreservesTaskMilestone`, and `DataMaintenanceUITests.testDataMaintenanceGoldenPath`, then exceeds the cap during cleanup. No T-1770 code touches these UI flows.

**Manual verification:** Not required. The injection seams exercise the exact intent paths with a writable in-memory context and deterministic failures.

## Prevention

- Catch typed validation/domain errors before the generic catch; generic infrastructure errors must map to `INTERNAL_ERROR`.
- Direct service lookup methods must use their injectable fetch seam.
- Keep create recovery (`insertOrDelete`) distinct from update/delete recovery (`saveOrRollback` / `safeRollback`) and assert no mutation at the intent boundary.

## Related

- T-1770
- T-1768 — `CreateTaskIntent` creation failure semantics
- T-1614 / T-1621 — deterministic `ModelFetching` seams and fail-closed storage handling
- T-650 — `UpdateTaskIntent` infrastructure-error convention
