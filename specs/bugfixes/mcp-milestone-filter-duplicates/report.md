# Bugfix Report: MCP Milestone Filter Duplicates

**Date:** 2026-03-03
**Status:** Fixed

## Description of the Issue

When using `query_tasks` via the MCP server with a `milestone` name filter but without a `project` filter, only tasks from one project's milestone were returned. If multiple projects had milestones with the same name (e.g., "v1.0"), tasks assigned to identically-named milestones in other projects were silently omitted.

**Reproduction steps:**
1. Create two projects (Alpha, Beta) each with a milestone named "v1.0"
2. Assign tasks to each project's "v1.0" milestone
3. Call `query_tasks` with `{"milestone": "v1.0"}` (no project filter)
4. Observe only tasks from one project's milestone are returned

**Impact:** MCP clients filtering tasks by milestone name across projects received incomplete results. This affected any automation or agent workflow that used milestone name filtering without explicitly scoping to a project.

## Investigation Summary

- **Symptoms examined:** `handleQueryTasks` in `MCPToolHandler.swift` collects all milestones matching the name but only uses the first match
- **Code inspected:** `MCPToolHandler.handleQueryTasks`, `MCPQueryFilters` struct, `MCPQueryFilters.matches()`
- **Hypotheses tested:** Single root cause confirmed — the filter type was `UUID?` (singular), so only one milestone ID could ever be passed to the filter

## Discovered Root Cause

The `MCPQueryFilters` struct used `milestoneId: UUID?` — a single optional UUID — to represent the milestone filter. When multiple milestones shared the same name across projects, the code in `handleQueryTasks` correctly found all matches but then discarded all but the first via `matching.first`.

**Defect type:** Logic error (data structure too narrow for the use case)

**Why it occurred:** The original implementation assumed milestone names would be unique across the entire data set, or that a project filter would always be present. The `MCPQueryFilters` struct was designed with a single-ID field because the single-project case was the primary use case considered.

**Contributing factors:** The milestone name filter was added after the initial query implementation. The cross-project scenario was not covered by tests.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPHelperTypes.swift` — Changed `milestoneId: UUID?` to `milestoneIds: Set<UUID>?` in the `MCPQueryFilters` struct. Updated the `from()` factory parameter and the `matches()` method to check set membership.
- `Transit/Transit/MCP/MCPToolHandler.swift` — Changed `milestoneFilter` from `UUID?` to `Set<UUID>?`. In the no-project-filter branch, collect all matching milestone IDs into a `Set` instead of taking only the first.

**Approach rationale:** Using `Set<UUID>` is the minimal change that correctly handles both single-milestone (with project filter) and multi-milestone (without project filter) cases. Set membership checks are O(1), so there is no performance concern.

**Alternatives considered:**
- Returning an error when milestone name is ambiguous without project filter — rejected because it would break existing workflows and the expected behaviour is to return all matching tasks
- Keeping `UUID?` and filtering in-memory after the main query — rejected because it would scatter filter logic across two locations

## Regression Test

**Test file:** `Transit/TransitTests/MCPMilestoneIntegrationTests.swift`
**Test name:** `queryTasksByMilestoneNameAcrossProjects`

**What it verifies:** When two projects each have a milestone with the same name and tasks assigned to those milestones, `query_tasks` with only a milestone name filter returns tasks from both projects.

A second test (`queryTasksByMilestoneNameWithProjectFilterReturnsOnlyThatProject`) verifies that adding a project filter correctly scopes the results to a single project.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPHelperTypes.swift` | Changed `milestoneId: UUID?` to `milestoneIds: Set<UUID>?` in struct and factory |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Collect all matching milestone IDs instead of just the first |
| `Transit/TransitTests/MCPMilestoneIntegrationTests.swift` | Added two regression tests for cross-project milestone filtering |

## Verification

**Automated:**
- [x] Regression test written
- [ ] Full test suite passes (Xcode toolchain issue prevents local test execution)
- [x] Linters/validators pass

**Manual verification:**
- Code review confirms the fix correctly handles both the single-project and cross-project cases
- The `milestoneDisplayId` path (which resolves to a single unique milestone) continues to work correctly via a single-element set

## Prevention

- When introducing filter parameters that resolve names to IDs, consider that names may not be globally unique
- Use collection types (Set/Array) for filter IDs from the start, even if the initial use case only needs one value
- Add cross-project test scenarios for any filter that accepts names rather than unique identifiers

## Related

- Transit ticket: T-292
