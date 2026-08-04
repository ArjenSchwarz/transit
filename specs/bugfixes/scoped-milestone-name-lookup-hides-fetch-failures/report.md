# Bugfix Report: Scoped Milestone Name Lookup Hides Fetch Failures

**Date:** 2026-08-05
**Status:** Fixed
**Ticket:** T-1675

## Description of the Issue

A project-scoped milestone name lookup must distinguish three outcomes: a valid no-match, a CloudKit-induced duplicate name, and an unreadable SwiftData store. The service already exposes that distinction through its throwing lookup and injected fetcher, but one shared assignment adapter collapsed an untyped storage error to the generic `"Failed to assign milestone"` hint. That prevented automation from receiving the exact retryable storage failure carried by the corresponding JSON and MCP create, update, and query paths.

**Reproduction steps:**
1. Construct `MilestoneService` with a deterministic `ModelFetching` implementation that throws.
2. Submit a project-scoped milestone-name lookup through the shared assignment path.
3. Observe a generic internal error instead of the underlying lookup failure.

**Impact:** Automation could not reliably identify the specific failed read or correlate retries across surfaces. A failure must not be mistaken for a normal missing milestone, ambiguity, validation error, or a completed mutation.

## Investigation Summary

### Phase 1 — Initial overview

The expected contract is `INTERNAL_ERROR` with the exact `Failed to look up milestone: <storage error>` hint for JSON intents and the same text in an MCP tool error. Valid no-match, ambiguity, project mismatch, identifier/field validation precedence, and unscoped cross-project query behavior must remain unchanged.

The focused macOS regression suite was red before the correction:

```text
MilestoneNameLookupFailureTests.jsonCreateAndUpdatePathsReturnExactLookupErrorWithoutMutation()
```

### Phase 2 — Systematic inspection

- `MilestoneService.findByName(_:in:)` already uses its injected `ModelFetching` seam. It returns `nil` only for a genuine no-match, throws `.ambiguousName` for duplicate project-scoped names, and propagates an infrastructure fetch error.
- `CreateTaskIntent`, `TaskUpdateValidator`, `IntentHelpers.resolveMilestone` (used by `UpdateMilestoneIntent`), MCP `create_task`, and MCP project-scoped `query_tasks` already translate an unexpected lookup failure as `Failed to look up milestone: <error>`.
- `IntentHelpers.assignMilestone(named:to:using:)` instead converted its generic catch to `INTERNAL_ERROR` with only `Failed to assign milestone`, losing the original failure text.
- T-1657 supplies the applicable surface-adapter pattern; T-1770 supplies the generic persistence classification and injected `ModelFetching` seam. Both commits are ancestors of this branch.

### Phase 3 — Root cause analysis

1. Why was the exact failure lost? The shared assignment helper used a generic fallback hint.
2. Why did other paths remain correct? Their generic catches retained the lookup-specific error text.
3. Why is that distinction required? A failing fetch is infrastructure state, not a missing milestone or invalid request.
4. Why was it deterministic to reproduce? T-1770 had already routed milestone name reads through an injectable fetcher, but MCP test setup did not expose that seam.

**Root cause:** one shared error adapter did not preserve the storage-error payload already carried by `MilestoneService.findByName(_:in:)`.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/IntentHelpers.swift` — maps an untyped name-lookup failure in shared assignment to `INTERNAL_ERROR` with the exact `Failed to look up milestone: <error>` hint.
- `Transit/TransitTests/MCPTestHelpers.swift` — exposes the existing `MilestoneService` fetcher injection through MCP test setup.
- `Transit/TransitTests/MilestoneNameLookupStorageFailureSurfaceTests.swift` — adds deterministic service, JSON create/update, shared assignment, and MCP create/update/project-scoped-query regressions with no-mutation assertions.

**Approach rationale:** The smallest safe change keeps the stable service contract and all existing typed error mappings. It aligns the one inconsistent adapter with T-1657/T-1770 without changing missing-name, ambiguity, project mismatch, validation precedence, or unscoped cross-project filtering.

**Alternatives considered:**
- Add a new service error case for storage failures — rejected because the raw fetch error already provides the required distinction and existing callers classify generic infrastructure errors as `INTERNAL_ERROR`.
- Change unscoped task queries to resolve a scoped milestone first — rejected because it would break the established cross-project same-name aggregation behavior.

## Regression Test

**Test file:** `Transit/TransitTests/MilestoneNameLookupStorageFailureSurfaceTests.swift`

**Tests:**
- `findByNamePropagatesInjectedFetchFailureInsteadOfReturningNoMatch`
- `jsonCreateAndUpdatePathsReturnExactLookupErrorWithoutMutation`
- `mcpCreateUpdateAndScopedQueryReturnExactLookupErrorWithoutMutation`

**What it verifies:** The deterministic fetch seam stays distinct from a no-match and yields the exact source error in every scoped JSON/MCP create, update, and query path while task and milestone state remain unchanged.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|---|---|
| `Transit/Transit/Intents/IntentHelpers.swift` | Preserve exact storage error text for shared name-based assignment. |
| `Transit/TransitTests/MCPTestHelpers.swift` | Allow MCP tests to inject the milestone service fetch seam. |
| `Transit/TransitTests/MilestoneNameLookupStorageFailureSurfaceTests.swift` | Add deterministic cross-surface error and no-mutation coverage. |
| `CHANGELOG.md` | Record the corrected automation failure contract. |

## Verification

**Automated:**
- [x] New focused regression suite failed before the fix.
- [x] Focused milestone lookup, task create/update, and MCP project-query suites pass after the fix.
- [x] Full macOS unit suite passes (`make test-quick`).
- [x] Linter and ownership guard pass (`make lint`).
- [x] iOS Simulator build passes (`make build-ios`).

**Manual verification:** Not required; deterministic in-memory SwiftData tests exercise the exact service and automation boundaries.

## Prevention

- Keep `nil` reserved for a valid scoped no-match; let `findByName(_:in:)` propagate storage failures and `.ambiguousName`.
- Catch typed domain errors before generic infrastructure errors, and preserve a source-specific lookup hint for the latter.
- Expose existing service seams through cross-surface test fixtures so an MCP adapter cannot silently diverge.

## Related

- T-1675
- T-1657 — project lookup storage-failure surface adapters
- T-1770 — persistence error classification and injected lookup seams
- T-1608 — unscoped MCP milestone-name fetch failures
