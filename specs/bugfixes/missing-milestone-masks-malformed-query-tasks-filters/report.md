# Bugfix Report: Missing Milestone Masks Malformed Query Tasks Filters

**Date:** 2026-08-05
**Status:** Fixed

## Description of the Issue

Historically, MCP `query_tasks` resolved `milestone` and `milestoneDisplayId` before validating several other supplied filters. A missing milestone returned a successful empty array, so malformed `status`, `not_status`, `type`, `priority`, `unfinished`, `search`, or `displayId` values were not rejected.

Merged T-1608 / PR #217 already corrected the production order, but its precedence regression used a failing milestone fetch rather than an actual missing milestone. The direct no-match combinations described by T-1816 were therefore unpinned.

**Reproduction steps (before PR #217):**
1. Call `query_tasks` with a non-existent milestone name or display ID.
2. Include a malformed downstream filter, for example `{ "milestone": "does-not-exist", "search": 42 }`.
3. Observe a successful `[]` instead of `search must be a string`.

**Impact:** A future reordering could silently reintroduce malformed-request masking while the existing suite still passed.

## Investigation Summary

- **Initial overview:** T-1816 is a coverage follow-up to the query validation-order correction in T-1608 / PR #217.
- **Systematic inspection:** `MCPToolHandler.handleQueryTasks` validates `milestoneDisplayId`, `milestone`, `status`, `not_status`, `type`, `priority`, `unfinished`, `search`, and `displayId` before either milestone lookup branch. The merged PR moved those checks ahead of resolution.
- **Root-cause analysis:** The existing `queryMilestoneFetchFailureDoesNotMaskMalformedStatus` test establishes the ordering indirectly against a throwing fetch, while `queryUnscopedMilestoneNameWithNoMatchReturnsEmptyArray` establishes valid no-match behavior separately. Neither combines a missing milestone with malformed filters.
- **Assumption verified:** Both the name no-match path and `milestoneDisplayId` no-match path return `[]` only after the shared validation block. The new matrix invokes both paths with every filter named by T-1816.

## Discovered Root Cause

**Defect type:** Missing direct regression coverage.

PR #217 fixed the functional defect by relocating validation before milestone resolution, but its regression selection did not exercise the two legitimate missing-milestone early-return paths together with every malformed filter. The behavior was correct in the current source; the protection against regression was incomplete.

## Resolution for the Issue

**Changes made:**
- `Transit/TransitTests/MCPQueryTasksValidationPrecedenceTests.swift` — adds `missingMilestonesDoNotMaskMalformedQueryFilters`, a 14-case matrix covering two missing milestone selectors and seven malformed filters.
- `CHANGELOG.md` — records the pinned validation-order contract.

**Approach rationale:** Add only the absent regression coverage. Modifying `MCPToolHandler` would duplicate PR #217's already-correct production logic and create unnecessary risk.

**Alternatives considered:**
- Change production validation order again — rejected; the current handler already has the required ordering.
- Test only one selector or one malformed filter — rejected; T-1816 explicitly concerns both milestone early-return paths and all listed filters.

## Regression Test

**Test file:** `Transit/TransitTests/MCPQueryTasksValidationPrecedenceTests.swift`
**Test name:** `missingMilestonesDoNotMaskMalformedQueryFilters`

**What it verifies:** For both `{ "milestone": "does-not-exist" }` and `{ "milestoneDisplayId": 999 }`, malformed `status`, `not_status`, `type`, `priority`, `unfinished`, `search`, and `displayId` return their field-specific validation error rather than a successful no-match array.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|---|---|
| `Transit/TransitTests/MCPQueryTasksValidationPrecedenceTests.swift` | Direct no-match/malformed-filter regression matrix. |
| `CHANGELOG.md` | Documents the regression contract. |
| `specs/bugfixes/missing-milestone-masks-malformed-query-tasks-filters/report.md` | Investigation and verification record. |

## Verification

**Automated:**
- [x] Existing production ordering from PR #217 was inspected in `MCPToolHandler.handleQueryTasks`.
- [x] New direct regression matrix passes (`make test-quick`).
- [x] SwiftLint and the SwiftData ownership guard pass (`make lint`).

A separate red run is not applicable: PR #217 already contains the production correction. This task adds the previously missing direct regression coverage for that implementation.

**Manual verification:** Not required; the MCP handler is invoked directly through its JSON-RPC test harness.

## Prevention

Keep validation ahead of every no-match early return, and pair any validation-order change with direct tests for each early-return path rather than only a throwing-storage variant.

## Related

- T-1816
- T-1608
- PR #217
