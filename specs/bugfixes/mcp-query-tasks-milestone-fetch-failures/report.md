# Bugfix Report: MCP Query Tasks Milestone Fetch Failures

**Date:** 2026-08-03
**Status:** Fixed

## Description of the Issue

MCP `query_tasks` silently returned a successful empty array when a query supplied a milestone name without a project scope and SwiftData failed while fetching milestones.

**Reproduction steps:**
1. Call `query_tasks` with a non-empty `milestone` name and no `project` or `projectId`.
2. Make the full-table milestone fetch throw.
3. Observe `[]` instead of an MCP tool error.

**Impact:** MCP clients could not distinguish a failed filter evaluation from a legitimate query with no matching tasks.

## Investigation Summary

- **Symptoms examined:** The no-project milestone-name branch used `try? ... ?? []`; later task-fetch failures and `query_milestones` already returned tool errors.
- **Code inspected:** `MCPToolHandler.handleQueryTasks`, `MCPQueryFilters`, `MilestoneService`, `MilestoneFetching`, MCP query tests, and all three `MCPToolHandler` construction callers.
- **Hypotheses tested:** The failure was isolated to the no-project milestone-name fetch. Project-scoped lookup, no-match results, cross-project ID aggregation, T-1938 ambiguity handling, malformed-input order, response serialization, and later task fetch failures use separate existing paths.

## Discovered Root Cause

**Defect type:** Error-handling logic error.

The no-project milestone-name branch converted a thrown `fetchAllMilestones()` error into an empty list with `try?`. Its empty-ID branch then returned `[]`, the same successful response used for a legitimate no-match.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift` — injects read seams for unscoped milestone names and display IDs, returns `Failed to fetch milestones: <error>` for failed unscoped-name reads, and returns `Failed to look up milestone: <error>` for unexpected display-ID lookup failures while retaining the normal no-match and duplicate-ID outcomes.
- `Transit/TransitTests/MCPTestHelpers.swift` — accepts both deterministic milestone read seams.
- `Transit/TransitTests/MCPQueryProjectNameTests.swift` — adds exact-error, no-false-success, malformed-filter precedence, and legitimate no-match regression coverage.

**Approach rationale:** The handler now follows the explicit storage-error contract used by `query_milestones` and the later `query_tasks` task fetch. It preserves valid no-match responses, cross-project aggregation, and scoped lookup behavior while making malformed filters fail before milestone resolution.

**Alternatives considered:**
- Keep `try?` and add logging — rejected because callers still receive an indistinguishable successful `[]`.
- Change shared service behavior — rejected because the defect is MCP response translation, and the existing service/API contract already throws.

## Independent Review Follow-up

The PR review found two adjacent paths that could still hide or mis-prioritize failures:

- `milestoneDisplayId` lookup now preserves its legitimate `milestoneNotFound` empty result and duplicate-ID error, while surfacing unexpected storage failures through a narrow injected `MilestoneDisplayIDFinding` seam.
- Every remaining `query_tasks` filter shape is validated before milestone resolution. This intentionally gives malformed filters precedence over milestone no-match, duplicate, or storage-failure outcomes; regression coverage proves an invalid status is not masked by a failing milestone fetch.

The follow-up coverage also directly proves that an unscoped milestone name with no matches still returns a successful empty array.

## Regression Test

**Test file:** `Transit/TransitTests/MCPQueryProjectNameTests.swift`
**Tests:**
- `queryMilestoneNameFetchFailureReturnsExactErrorInsteadOfEmptyArray`
- `queryMilestoneDisplayIDFetchFailureReturnsExactErrorInsteadOfEmptyArray`
- `queryUnscopedMilestoneNameWithNoMatchReturnsEmptyArray`
- `queryMilestoneFetchFailureDoesNotMaskMalformedStatus`

The deterministic seams verify `isError == true` with the exact name- and display-ID failure text, preserve a legitimate no-match empty array, and prove input validation is not masked by a failing milestone fetch. Before the original fix, the unscoped-name failure returned a successful `[]`.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Injected milestone read seams, surfaced name/display-ID storage failures, and validates filter shapes before milestone resolution. |
| `Transit/TransitTests/MCPTestHelpers.swift` | Passed deterministic milestone read seams into MCP handler tests. |
| `Transit/TransitTests/MCPQueryProjectNameTests.swift` | Added exact-error, no-false-success, no-match, and validation-order regression coverage. |
| `CHANGELOG.md` | Recorded the complete fixed MCP error and validation-order contract. |

## Verification

**Automated:**
- [x] Regression test fails before the fix (`make test-quick`)
- [x] Regression test passes after the fix (`make test-quick`)
- [x] `make test-quick` passes
- [x] `make lint` passes

**Manual verification:** Not required; the handler is exercised directly with an injected failing store seam.

## Prevention

Milestone-resolution paths must propagate unexpected storage errors as tool errors rather than recover with empty collections when an empty result is a valid response. Validate every filter shape before resolving milestones so lookup outcomes cannot mask malformed input.

## Related

- T-1608
- T-292 (cross-project same-name milestone aggregation)
- T-1938 (project-scoped milestone-name ambiguity handling)
