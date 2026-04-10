# Bugfix Report: MCP Milestone Malformed milestoneId

**Date:** 2026-04-10
**Status:** Fixed

## Description of the Issue

The MCP `update_milestone` and `delete_milestone` handlers silently ignore a malformed `milestoneId` parameter (e.g., "not-a-uuid", "abc") and return a generic "Provide either displayId (integer) or milestoneId (UUID string)" error instead of a specific "milestoneId must be a valid UUID" error.

**Reproduction steps:**
1. Call MCP `update_milestone` with `{"milestoneId": "not-a-uuid", "name": "v2.0"}`
2. Observe the error says "Provide either displayId (integer) or milestoneId (UUID string)" instead of indicating the milestoneId is invalid

**Impact:** Low severity. The handler does return an error (not a silent success), but the error message is misleading. An agent receiving "Provide either..." when it already provided a milestoneId may loop retrying with the same invalid value.

## Investigation Summary

- **Symptoms examined:** Error messages from update_milestone and delete_milestone with invalid UUID in milestoneId
- **Code inspected:** MCPToolHandler.resolveMilestone(from:), IntentHelpers.resolveMilestone(from:...), DeleteMilestoneIntent.execute(input:...)
- **Hypotheses tested:** Whether the combined conditional pattern silently drops invalid inputs

## Discovered Root Cause

The resolveMilestone(from:) method in MCPToolHandler uses a combined conditional for milestoneId validation that silently drops invalid UUIDs, falling through to a generic error.

**Defect type:** Missing validation

**Why it occurred:** The code predates the T-665 pattern of separating presence checks from format validation. T-634 fixed this for displayId but did not address the milestoneId path.

## Resolution for the Issue

**Changes made:**
- Transit/Transit/MCP/MCPToolHandler.swift - Split combined conditional in resolveMilestone(from:) into separate presence check and UUID validation

**Approach rationale:** Follows the established T-665 pattern.

## Regression Test

**Test file:** Transit/TransitTests/MCPNonIntegerDisplayIdTests.swift

**Run command:** make test-quick

## Affected Files

| File | Change |
|------|--------|
| Transit/Transit/MCP/MCPToolHandler.swift | Split milestoneId validation in resolveMilestone |
| Transit/TransitTests/MCPNonIntegerDisplayIdTests.swift | Add regression tests for malformed milestoneId |

## Verification

- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Related

- T-634: Reject non-integer displayId in MCP query tools
- T-665: Validate projectId in milestone queries
