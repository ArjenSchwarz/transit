# Bugfix Report: App Entity Queries Hide Fetch Failures

**Date:** 2026-08-03
**Status:** Fixed

## Description of the Issue

Visual Shortcuts `AppEntity` queries returned a successful empty array when their SwiftData full-table fetch failed. This made a storage problem indistinguishable from an empty project/task store or an unresolved created task.

**Reproduction steps:**
1. Invoke any affected `entities(for:)` or `suggestedEntities()` resolver with a deterministic failing project/task fetcher.
2. Observe that the resolver catches the fetch error with `try?`.
3. Observe that it returns `[]` instead of propagating the failure through the existing `async throws` App Intents API.

**Impact:** Shortcuts pickers and task-creation result resolution could silently display no data during a storage failure, masking an actionable failure as a valid empty result.

## Investigation Summary

### Phase 1: Initial overview

Expected behavior is for failures from the project/task storage fetch to surface through the existing throwing EntityQuery entry points. Actual behavior coalesced every error into `[]`. The problem occurs on each invocation of the affected resolver when SwiftData cannot complete the full-table fetch.

### Phase 2: Systematic inspection

- **Error handling:** `ProjectEntityQuery.entities(for:)` and `suggestedEntities()` used `(try? projectService.fetchAllProjects(...)) ?? []`.
- **Error handling:** `TaskEntityQuery.entities(for:)` and `suggestedEntities()` used `(try? taskService.fetchAllTasks()) ?? []`.
- **Error handling:** `TaskCreationResultQuery.entities(for:)` and `suggestedEntities()` used the same task-fetch suppression.
- **Boundary behavior to retain:** Empty or wholly invalid identifier arrays return before fetching; task entity/result conversion intentionally skips records missing their project relationship.
- **Ordering and limits to retain:** Project suggestions retain name ordering; task suggestions retain their existing date ordering and ten-item limit.

A focused macOS test suite added six deterministic failure cases—one for each resolver entry point—and all six failed before the fix because no error was thrown.

### Phase 3: Root cause analysis

1. Why did a storage failure look like no data? The fetch errors were converted to optional `nil` with `try?`.
2. Why did `nil` become no data? Each query coalesced it to `[]`.
3. Why was that misleading? `[]` is also the valid result for an empty store, unmatched identifiers, and intentionally skipped partial records.
4. Why could the framework have reported the error? The conforming `EntityQuery` methods already use `async throws`.
5. **Root cause:** Resolver helpers suppressed the only storage operation that can distinguish unreadable storage from valid empty data, despite their callers exposing a throwing App Intents contract.

**Defect type:** Silent error handling / incorrect error recovery.

**Assumptions validated:** The query helpers are the only callers of their full-table resolver paths; `FindTasksIntent` uses the separate `entities(from:)` conversion helper and is unaffected. T-2081 prefix-before-filtering behavior is unrelated and remains out of scope.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/Shared/Entities/ProjectEntityQuery.swift` — added a narrow `ProjectFetching` test seam; both resolvers and their existing `async throws` entry points now rethrow full-table fetch failures.
- `Transit/Transit/Intents/Shared/Entities/TaskEntityQuery.swift` — reused the existing `TaskFetching` seam and rethrows fetch failures without changing filtering, ordering, limits, or partial-entity skipping.
- `Transit/Transit/Intents/Shared/Results/TaskCreationResult.swift` — rethrows fetch failures while retaining created-result conversion and missing-project skipping.
- `Transit/TransitTests/EntityQueryFetchFailureTests.swift` — adds deterministic failure coverage for all six resolver paths.

**Approach rationale:** The App Intents-facing methods already promised `async throws`, so forwarding the original storage error is the smallest correction. Identifier validation remains before the fetch and conversion errors remain intentionally local to individual records.

**Alternatives considered:**
- Returning a typed error entity or converting failures to an empty result — rejected because either changes the existing App Intents contract or repeats the ambiguity that caused the bug.
- Changing T-2081's prefix-before-filtering behavior — excluded as unrelated query-selection scope.

## Regression Test

**Test file:** `Transit/TransitTests/EntityQueryFetchFailureTests.swift`

**Test names:**
- `projectEntitiesForIdentifiersPropagatesFetchFailure`
- `projectSuggestedEntitiesPropagatesFetchFailure`
- `taskEntitiesForIdentifiersPropagatesFetchFailure`
- `taskSuggestedEntitiesPropagatesFetchFailure`
- `taskCreationResultEntitiesForIdentifiersPropagatesFetchFailure`
- `taskCreationResultSuggestedEntitiesPropagatesFetchFailure`

**What it verifies:** Each affected resolver rethrows a deterministic storage fetch error rather than returning a successful empty result.

**Red run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/EntityQueryFetchFailureTests`

## Affected Files

| File | Change |
|---|---|
| `Transit/Transit/Intents/Shared/Entities/ProjectEntityQuery.swift` | Propagate project fetch failures through the query contract. |
| `Transit/Transit/Intents/Shared/Entities/TaskEntityQuery.swift` | Propagate task fetch failures through the query contract. |
| `Transit/Transit/Intents/Shared/Results/TaskCreationResult.swift` | Propagate task fetch failures when resolving created-task results. |
| `Transit/TransitTests/EntityQueryFetchFailureTests.swift` | Six deterministic regression tests. |

## Verification

**Automated:**
- [x] Regression test fails before the fix (six expected failure-path tests)
- [x] Focused regression suite passes: `TransitTests/EntityQueryFetchFailureTests`
- [x] macOS unit suite passes: `make test-quick`
- [x] Linter/ownership guard passes: `make lint`
- [x] macOS production build passes: `make build-macos`
- [ ] Full iOS suite passes — `make test` exceeded the 10-minute command cap after compiling and running the relevant tests; the new `EntityQueryFetchFailureTests` passed during that run.
- [ ] UI suite passes — `make test-ui` reproducibly reports unrelated failures in `TransitUITests.testClearAll`, `TransitUITests.testEditViewPreservesTaskMilestone`, and `DataMaintenanceUITests.testDataMaintenanceGoldenPath`, then exceeds the command cap during cleanup. This fix does not modify those UI flows.

**Manual verification:** Not required; the regressions invoke the same EntityQuery resolver code used by Shortcuts.

## Prevention

- Never use `(try? fetch(...)) ?? []` where callers must distinguish an unreadable store from a valid empty result.
- Give query helpers an injectable throwing fetch seam so failure behavior stays deterministic under test.

## Related

- Transit ticket T-1607
- T-1566 (equivalent JSON query-intent failure handling)
- T-2081 (prefix-before-filtering scope explicitly excluded)
