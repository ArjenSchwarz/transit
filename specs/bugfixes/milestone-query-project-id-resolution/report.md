# Bugfix Report: Milestone Query Project ID Resolution

**Date:** 2026-08-05
**Status:** Fixed

## Description of the Issue

`query_milestones` and `QueryMilestonesIntent` validate that a supplied `projectId` is syntactically a UUID, but do not verify that it identifies a stored project. A valid random UUID is used directly as a milestone filter, so both the full-list and `displayId` query paths report a successful empty array.

**Reproduction steps:**
1. Call MCP `query_milestones` or `QueryMilestonesIntent` with a well-formed UUID that is not a project.
2. Optionally include a `displayId` for an existing milestone.
3. Observe a successful empty array instead of the established project-not-found error.

**Impact:** Automation cannot distinguish a genuine no-match milestone query from a typo, stale UUID, or deleted project. Project-store failures are also skipped rather than surfaced when only `projectId` is supplied.

## Investigation Summary

- **Symptoms examined:** Valid missing project UUIDs return `[]`; malformed UUIDs are already rejected and name-based project filters already call `ProjectService`.
- **Code inspected:** `Transit/Transit/MCP/MCPToolHandler.swift` (`resolveProjectFilter`), `Transit/Transit/Intents/QueryMilestonesIntent.swift` (`resolveProjectFilter`), `ProjectService.findProject`, existing task-query parity tests, and milestone query tests.
- **Hypotheses tested:** The display-ID branch was not the source: both full and display-ID paths resolve the project filter first. The gap is specific to a successful UUID parse being treated as successful project resolution.

### Fagan Inspection

1. **Initial overview:** Parsing a UUID proves only its format, not resource existence. The expected behavior is the same project-not-found or storage-failure contract already used by project-name filters and task queries.
2. **Systematic inspection:** MCP returns `.resolved(pid)` immediately for parsed IDs. The App Intent returns `.resolved(projectId)` immediately for parsed IDs. Neither branch can receive `ProjectLookupError.notFound` or `.storageFailure`; name branches already map those outcomes.
3. **Five whys:** Why is `[]` returned? The UUID becomes a filter with no matching milestones. Why does it become a filter? Resolver success is based only on UUID parsing. Why is project absence not detected? `ProjectService.findProject(id:)` is not called. Why is that inconsistent? Name filters and task queries use semantic project lookup, but these ID branches omitted it. **Root cause:** missing semantic project-existence resolution after syntactic UUID validation.
4. **Solution and verification:** Resolve every syntactically valid milestone-query `projectId` through `ProjectService.findProject(id:)`; map its existing errors through `IntentHelpers.mapProjectLookupError`; retain current malformed-ID validation and ID-over-name precedence. Regression tests cover MCP and App Intent full-list/display-ID paths, missing IDs, storage failures, malformed-ID non-fallback, and valid-ID name precedence.

## Discovered Root Cause

**Defect type:** Missing validation / error-propagation gap.

**Why it occurred:** The two resolvers conflated syntactic UUID validation with semantic project resolution. They directly reused the parsed UUID for filtering instead of using the existing project service.

**Contributing factors:** The successful empty-array response is also valid for unmatched milestone filters, masking the missing-project case. The broader malformed project and storage work tracked by T-2077 is intentionally outside this fix; T-1824 changes only well-formed `projectId` existence resolution and its direct errors.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift:884` — after `projectId` syntax validation, resolve the ID with `ProjectService.findProject(id:)`; map its existing lookup error to the MCP tool-error text before either milestone query path runs.
- `Transit/Transit/Intents/QueryMilestonesIntent.swift:182` — resolve the parsed ID with the same service and map its existing lookup error to the established `IntentError` JSON response.
- `Transit/TransitTests/QueryMilestonesProjectIDResolutionTests.swift` — add cross-surface full-list and `displayId` coverage for missing IDs, storage failures, malformed-ID non-fallback, and ID-over-name precedence.

**Approach rationale:** The service is the established authority for exact UUID existence and storage errors. Reusing its `ProjectLookupError` mapping keeps current response codes and hints stable instead of creating a milestone-specific error path.

**Alternatives considered:**
- Treating a valid but unmatched UUID as an ordinary empty milestone filter — rejected because callers cannot distinguish a stale/mistyped project from a legitimate no-match query.
- Expanding validation for other malformed project-field shapes — rejected as broader T-2077 scope.

## Regression Test

**Test file:** `Transit/TransitTests/QueryMilestonesProjectIDResolutionTests.swift`

**Test names:**
- `missingProjectIdReturnsExactNotFoundAcrossFullAndDisplayIDQueries`
- `projectIdSyntaxAndNamePrecedenceAreConsistentAcrossFullAndDisplayIDQueries`
- `projectLookupStorageFailureReturnsExactErrorsAcrossFullAndDisplayIDQueries`

**What it verifies:** Both query surfaces resolve valid IDs through `ProjectService`, retain syntax/name precedence, and return exact not-found/storage contracts before either milestone query path.

**Run command:** `run_silent make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Resolve valid query `projectId` values through `ProjectService`. |
| `Transit/Transit/Intents/QueryMilestonesIntent.swift` | Resolve valid query `projectId` values through `ProjectService`. |
| `Transit/TransitTests/QueryMilestonesProjectIDResolutionTests.swift` | Cross-surface regression coverage. |
| `CHANGELOG.md` | T-1824 Unreleased entry. |
| `specs/bugfixes/milestone-query-project-id-resolution/report.md` | Investigation and verification record. |

## Verification

**Automated:**
- [x] `run_silent make test-quick` — passed on macOS, including the new T-1824 cross-surface regression suite.
- [x] `run_silent make lint` — passed, including the SwiftData ownership guard.
- [ ] `run_silent make test` — began a clean iOS Simulator build and test execution with no reported failures, but exceeded the harness's 120-second command limit before completion on two attempts.
- [ ] `run_silent make test-ui` — not run after the full iOS suite time limit; no UI code changed.

**Manual verification:** Reviewed both resolver paths to confirm project resolution occurs before the already-shared full-list and `displayId` query branches.

## Prevention

- Treat a parsed identifier as syntax validation only; resolve it through its service before filtering when the API contract requires entity existence.
- Keep MCP and JSON App Intent tests paired for public error-contract changes.

## Related

- T-1824 — Milestone queries accept nonexistent projectId.
- T-1783 — Task-query project-ID existence behavior used as the established precedent.
- T-2077 — Broader malformed project/storage scope, intentionally not modified here.
