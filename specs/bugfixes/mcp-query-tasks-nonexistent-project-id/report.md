# Bugfix Report: MCP query_tasks accepts nonexistent projectId

**Date:** 2026-08-02
**Status:** In Progress

## Description of the Issue

MCP `query_tasks` validates that `projectId` has UUID syntax but does not verify that the referenced project exists. A well-formed UUID for a nonexistent project is treated as an ordinary filter, so the handler returns a successful empty array instead of the established project-not-found error used by project-name filtering and `QueryTasksIntent`.

**Reproduction steps:**
1. Call MCP `query_tasks` with `{"projectId":"<well-formed UUID not present in the store>"}`.
2. Observe that the response is successful and contains `[]`.
3. Compare with an unknown project name or the equivalent `QueryTasksIntent` request, which returns a project-not-found error.

**Impact:** MCP callers cannot distinguish a valid project filter with no matching tasks from a stale or nonexistent project identifier. This creates inconsistent behavior across automation surfaces and can hide stale project references.

## Investigation Summary

The investigation followed the systematic debugging workflow:

- **Symptoms examined:** A valid random UUID returned a non-error empty array from MCP `query_tasks`; malformed UUIDs were already rejected.
- **Code inspected:** `MCPToolHandler.handleQueryTasks`, `MCPQueryFilters.matches`, `ProjectService.findProject`, `QueryTasksIntent.validateProjectFilter`, and the existing MCP/intent query tests.
- **Hypotheses tested:** The filter matcher was not swallowing an error; it correctly compares task project IDs. The defect is earlier: the MCP UUID branch bypasses project lookup entirely. Name-based MCP filtering and the intent path already resolve the project and map a missing record to project-not-found.

## Discovered Root Cause

**Defect type:** Missing validation / inconsistent control flow.

**Why it occurred:** `handleQueryTasks` calls `parseProjectIdArgument` to validate UUID shape, then assigns the parsed UUID directly to `projectFilter`. It never calls `ProjectService.findProject(id:)` for the UUID branch. The later in-memory filter therefore has no way to know whether the UUID identifies a stored project.

**Contributing factors:** MCP and App Intent query paths evolved separately. Existing validation focused on rejecting malformed UUID values, while the name-based MCP path already performed existence resolution.

## Resolution for the Issue

_To be completed after the implementation and verification phases._

## Regression Test

**Test file:** `Transit/TransitTests/MCPQueryProjectNameTests.swift`
**Test name:** `queryByNonexistentProjectIdMatchesIntentProjectNotFound`

**What it verifies:** A well-formed nonexistent MCP `projectId` returns an error, and the MCP hint matches the `QueryTasksIntent` project-not-found response. The existing malformed UUID coverage remains unchanged.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Resolve valid `projectId` through `ProjectService` before filtering. |
| `Transit/TransitTests/MCPQueryProjectNameTests.swift` | Add MCP regression and cross-surface parity assertion. |
| `CHANGELOG.md` | Record the unreleased T-1783 fix. |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Confirm malformed UUID input still returns the existing validation error.
- Confirm valid existing UUID, project-name, and unrelated filters retain their current behavior.

## Prevention

**Recommendations to avoid similar bugs:**
- Separate identifier-shape validation from identifier-existence validation in query handlers.
- Keep MCP and App Intent project-filter contracts covered by parity tests.

## Related

- Transit ticket: T-1783
