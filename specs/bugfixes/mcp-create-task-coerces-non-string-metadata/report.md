# Bugfix Report: MCP create_task Coerces Non-String Metadata Values

**Date:** 2026-04-10
**Status:** Fixed

## Description of the Issue

The MCP `create_task` tool handler coerces non-string metadata values into their Swift string interpolation representations instead of dropping them. This produces meaningless stringified values like `"1"` for integers or `"(\"a\", \"b\")"` for arrays, diverging from the App Intent path which correctly ignores non-string metadata entries.

**Reproduction steps:**
1. Call MCP `create_task` with `metadata: {"priority": 1, "labels": ["a", "b"], "owner": "sam"}`
2. Query the created task's metadata

**Expected:** `{"owner": "sam"}` (non-string values dropped)
**Actual:** `{"priority": "1", "labels": "(\"a\", \"b\")", "owner": "sam"}` (non-string values coerced)

**Impact:** Metadata integrity issue. Agents or MCP clients sending mixed-type metadata get silently corrupted data stored on tasks, with no indication that values were mangled.

## Investigation Summary

- **Symptoms examined:** MCP and App Intent paths produce different metadata for identical input
- **Code inspected:** `MCPToolHandler.stringMetadata(from:)` (line 817-820), `IntentHelpers.stringMetadata(from:)` (line 28-41)
- **Hypotheses tested:** The MCP handler has its own private `stringMetadata` that uses string interpolation instead of filtering non-string values

## Discovered Root Cause

`MCPToolHandler` has a private `stringMetadata(from:)` method that converts every metadata value to a string via Swift string interpolation, while `IntentHelpers.stringMetadata(from:)` correctly filters out non-string values with a guard clause.

**Defect type:** Inconsistent implementation (duplicate logic with different behavior)

**Why it occurred:** When the MCP handler was originally written, it implemented its own metadata extraction rather than reusing the shared `IntentHelpers.stringMetadata` utility. The two implementations diverged in their handling of non-string values.

**Contributing factors:** The MCP tool definition schema describes metadata as "Key-value metadata (optional, string values)", which implies string values are expected, but the handler did not enforce this contract.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift:184` - Replace `stringMetadata(from:)` call with `IntentHelpers.stringMetadata(from:)`
- `Transit/Transit/MCP/MCPToolHandler.swift:817-820` - Remove the private `stringMetadata(from:)` method

**Approach rationale:** Reuse the existing `IntentHelpers.stringMetadata` which already implements the correct behavior and is well-tested. This eliminates the duplicate code and ensures consistent behavior across MCP and App Intent paths.

**Alternatives considered:**
- Add validation that returns an error for non-string metadata values - Rejected because the App Intent path already established the convention of silently dropping non-string values, and changing that contract would be a breaking change

## Regression Test

**Test file:** `Transit/TransitTests/MCPToolHandlerTests.swift`
**Test names:** `createTaskDropsNonStringMetadataValues`, `createTaskPreservesAllStringMetadata`, `createTaskMetadataAllNonStringYieldsNoMetadata`

**What it verifies:**
- Mixed-type metadata: only string values are preserved, non-string values are dropped
- All-string metadata: all entries are preserved
- All-non-string metadata: no metadata stored on the task

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Replace private `stringMetadata` with `IntentHelpers.stringMetadata` |
| `Transit/TransitTests/MCPCreateTaskMetadataTests.swift` | Add three regression tests for metadata handling (new file) |
| `Transit/TransitTests/MCPToolHandlerTests.swift` | Remove metadata tests (moved to dedicated file) |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (4 pre-existing failures unrelated to this change)
- [x] Linters/validators pass (1 pre-existing superfluous_disable_command warning unrelated)

## Prevention

**Recommendations to avoid similar bugs:**
- Prefer reusing shared helpers (`IntentHelpers`) over implementing private duplicates in handlers
- When adding MCP handler functionality that parallels App Intent behavior, check `IntentHelpers` for existing implementations first

## Related

- T-723: MCP create_task coerces non-string metadata values
