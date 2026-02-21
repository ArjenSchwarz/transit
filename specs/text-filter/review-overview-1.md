# PR Review Overview - Iteration 1

**PR**: #41 | **Branch**: T-180/text-filter | **Date**: 2026-02-21

## Valid Issues

### PR-Level Issues

#### Issue 1: Whitespace trimming inconsistency
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "The dashboard trims `.whitespaces`, while MCP and App Intent trim `.whitespacesAndNewlines`. For consistency across all three layers (and because the MCP/Intent approach is more correct), the dashboard could use `.whitespacesAndNewlines` too."
- **Validation**: Correct. Both `effectiveSearchText` and `DashboardLogic.buildFilteredColumns` use `.whitespaces` while MCP/Intent uses `.whitespacesAndNewlines`. While newlines can't be typed in the search bar, consistency is worth maintaining. Simple one-line fix in two places.

#### Issue 2: `search` + `displayId` interaction is untested
- **Type**: discussion comment
- **Reviewer**: @claude
- **Comment**: "When both `search` and `displayId` are provided, the single-task lookup runs first, then `filters.matches(task)` applies the search filter. A search that doesn't match the looked-up task returns an empty array. This is the correct behaviour, but since it's explicitly called out as non-obvious it deserves a test case."
- **Validation**: Correct. The implementation notes call this out as non-obvious, and the code path at `MCPToolHandler.swift:232-244` is untested. Adding a test for the match and non-match cases covers this edge case.

## Invalid/Skipped Issues

### Issue A: `effectiveSearch` naming / flatMap style
- **Location**: PR-level
- **Reviewer**: @claude
- **Comment**: Suggested using `flatMap`/`nilIfEmpty` instead of the current two-step pattern in `QueryTasksIntent`.
- **Reason**: Reviewer explicitly marked as "not a blocker — just a style note". Current pattern is clear and consistent with the MCP handler.

### Issue B: Missing empty state (`ContentUnavailableView.search`)
- **Location**: PR-level
- **Reviewer**: @claude
- **Comment**: Worth tracking as a follow-up since empty columns with no message could feel broken.
- **Reason**: Reviewer acknowledges this is "fine for V1" and it's already called out as deferred in the smolspec.
