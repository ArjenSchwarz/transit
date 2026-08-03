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
- `Transit/Transit/MCP/MCPToolHandler.swift` — injects the existing `MilestoneFetching` seam and returns `Failed to fetch milestones: <error>` when unscoped milestone-name resolution cannot read storage.
- `Transit/TransitTests/MCPTestHelpers.swift` — accepts the milestone fetcher seam.
- `Transit/TransitTests/MCPQueryProjectNameTests.swift` — adds deterministic failure coverage that asserts the exact tool error and rejects false success.

**Approach rationale:** The handler now follows the same explicit full-table fetch error contract used by `query_milestones` and the later `query_tasks` task fetch. It changes only the previously masked failure branch, preserving valid `[]` no-match responses and all existing filter behavior.

**Alternatives considered:**
- Keep `try?` and add logging — rejected because callers still receive an indistinguishable successful `[]`.
- Change shared service behavior — rejected because the defect is MCP response translation, and the existing service/API contract already throws.

## Regression Test

**Test file:** `Transit/TransitTests/MCPQueryProjectNameTests.swift`
**Test name:** `queryMilestoneNameFetchFailureReturnsExactErrorInsteadOfEmptyArray`

The test uses a deterministic `MilestoneFetching` failure and verifies `isError == true` with the exact text `Failed to fetch milestones: simulated milestone fetch failure`; before the fix, the Makefile test target failed because the handler returned successful `[]`.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Injected the milestone fetch seam and surfaced unscoped name-resolution failures. |
| `Transit/TransitTests/MCPTestHelpers.swift` | Passed deterministic milestone fetchers into MCP handler tests. |
| `Transit/TransitTests/MCPQueryProjectNameTests.swift` | Added no-false-success exact-error regression coverage. |
| `CHANGELOG.md` | Recorded the fixed MCP error contract. |

## Verification

**Automated:**
- [x] Regression test fails before the fix (`make test-quick`)
- [x] Regression test passes after the fix (`make test-quick`)
- [x] `make test-quick` passes
- [x] `make lint` passes

**Manual verification:** Not required; the handler is exercised directly with an injected failing store seam.

## Prevention

Full-table query paths must propagate storage errors as tool errors rather than recover with empty collections when an empty result is a valid response.

## Related

- T-1608
- T-292 (cross-project same-name milestone aggregation)
- T-1938 (project-scoped milestone-name ambiguity handling)
