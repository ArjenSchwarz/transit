# Bugfix Report: Display-ID Queries Hide Storage Lookup Failures

**Date:** 2026-08-05  
**Status:** Fixed  
**Ticket:** T-1862

## Description of the Issue

The single-record `displayId` paths in `QueryTasksIntent`, `QueryMilestonesIntent`, and MCP `query_milestones` treated every lookup error other than a duplicate identifier as a valid empty result (`[]`). A caller therefore could not distinguish a truly absent task or milestone from an unreadable SwiftData store.

**Reproduction steps:**
1. Inject a `ModelFetching` implementation that throws into `TaskService` or `MilestoneService`.
2. Query a single task or milestone using a `displayId`.
3. Observe a successful empty array instead of `INTERNAL_ERROR` (App Intents) or an MCP tool error.

**Impact:** Automations could incorrectly act on a transient or persistent storage failure as though the target record did not exist, potentially taking unsafe follow-up actions.

## Investigation Summary

### Phase 1 — Initial overview

Expected behavior is three distinct outcomes: explicit service not-found errors return `[]`; duplicate display IDs keep their existing corruption error; every other lookup failure is surfaced as an internal/tool error. T-1657 and T-1675 establish that infrastructure failures must remain distinct from valid no-match results and preserve source-specific lookup text.

The focused test suite was red before the implementation:

```text
DisplayIDLookupStorageFailureTests.queryTasksDisplayIdClassifiesNotFoundDuplicateAndStorageFailure()
DisplayIDLookupStorageFailureTests.queryMilestonesDisplayIdClassifiesOutcomesAcrossIntentAndMCP()
```

### Phase 2 — Systematic inspection

- `TaskService.findByDisplayID` and `MilestoneService.findByDisplayID` already distinguish `taskNotFound` / `milestoneNotFound`, `duplicateDisplayID`, and thrown SwiftData errors through their injected `ModelFetching` seams.
- The full-table query paths already map fetch failures to `INTERNAL_ERROR` or MCP tool errors.
- `QueryTasksIntent` caught duplicates explicitly but mapped all remaining errors, including storage failures, to `[]`.
- `QueryMilestonesIntent` and MCP `lookupMilestoneByDisplayId` had the same catch-all-empty behavior.
- Existing MCP test setup already exposes `MilestoneService`'s injected fetcher, matching T-1675, so no new production seam was necessary.

### Phase 3 — Root cause analysis

1. Why did unreadable storage appear as no match? The display-ID adapters used a generic catch that returned `[]`.
2. Why did the generic catch include infrastructure failures? It did not first match the service's explicit not-found case.
3. Why is that incorrect? `[]` is a successful query result and must be reserved for a verified missing record or a filter mismatch.
4. Why was the defect limited to these paths? The adjacent full-table and MCP task display-ID paths already preserve unexpected fetch failures.
5. Why did it persist? Regression tests covered ordinary no-match and duplicate behavior but not a failing direct-lookup seam across these adapters.

**Root cause:** three single-record display-ID adapters collapsed a typed absence result and an untyped storage failure into the same successful empty-array response.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/QueryTasksIntent.swift` — catches only `TaskService.Error.taskNotFound` as `[]`; unexpected lookup failures now return `INTERNAL_ERROR` with `Failed to look up task: <error>`.
- `Transit/Transit/Intents/QueryMilestonesIntent.swift` — catches only `MilestoneService.Error.milestoneNotFound` as `[]`; unexpected lookup failures now return `INTERNAL_ERROR` with `Failed to look up milestone: <error>`.
- `Transit/Transit/MCP/MCPToolHandler.swift` — MCP `query_milestones` now returns `Failed to look up milestone: <error>` for unexpected single-record lookup failures.
- `Transit/TransitTests/DisplayIDLookupStorageFailureTests.swift` — adds deterministic, exact-contract tests for not-found, duplicate, and injected storage-failure outcomes across the affected JSON and MCP surfaces.

**Approach rationale:** This is the smallest change that reuses existing service seams and error contracts. It follows T-1657/T-1675 by catching typed domain outcomes first and preserving unexpected storage errors without changing the service APIs or pre-existing duplicate wording.

**Alternatives considered:**
- Return `[]` for all lookup failures — rejected because it makes store failures indistinguishable from a valid no-match.
- Introduce a new service error case — rejected because raw fetch errors already flow through the injected seam and established callers classify them as internal errors.
- Change MCP `query_tasks` — rejected because its display-ID path already returns a tool error for unexpected lookup failures and is outside this ticket's scope.

## Regression Test

**Test file:** `Transit/TransitTests/DisplayIDLookupStorageFailureTests.swift`

**Tests:**
- `queryTasksDisplayIdClassifiesNotFoundDuplicateAndStorageFailure`
- `queryMilestonesDisplayIdClassifiesOutcomesAcrossIntentAndMCP`

**What it verifies:** Exact no-match arrays and duplicate errors remain unchanged, while deterministic `ModelFetching` failures produce the source-specific `INTERNAL_ERROR` payload or MCP tool error rather than a false successful `[]`.

**Focused run command:**

```bash
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=macOS' \
  -only-testing:TransitTests/DisplayIDLookupStorageFailureTests
```

## Affected Files

| File | Change |
|---|---|
| `Transit/Transit/Intents/QueryTasksIntent.swift` | Separates task not-found from unexpected lookup failure. |
| `Transit/Transit/Intents/QueryMilestonesIntent.swift` | Separates milestone not-found from unexpected lookup failure. |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Returns a lookup tool error for an unexpected milestone lookup failure. |
| `Transit/TransitTests/DisplayIDLookupStorageFailureTests.swift` | Exact cross-surface regression coverage. |
| `CHANGELOG.md` | Records the corrected public automation contract. |

## Verification

**Automated:**
- [x] Focused regression suite failed before the production change.
- [x] Focused regression suite passed after the production change.
- [x] Full macOS unit suite passes (`make test-quick`).
- [x] SwiftLint and the SwiftData ownership guard pass (`make lint`).
- [x] iOS Simulator build passes (`make build-ios`).

**Manual verification:** Not required. The injected `ModelFetching` seam deterministically exercises the failing storage branch without relying on a corrupted production store.

## Prevention

- Reserve successful `[]` results for an explicit typed not-found outcome or post-lookup filter mismatch.
- Catch domain errors before generic infrastructure failures and preserve a source-specific error message for the latter.
- Add an injected-seam regression whenever a single-record query adapter adds or changes error mapping.

## Related

- T-1862
- T-1657 — project lookup storage failures remain distinct from no match.
- T-1675 — scoped milestone lookup failures preserve exact source-specific errors.
- T-1770 — generic persistence failures map to `INTERNAL_ERROR`.
