# Bugfix Report: Intent JSON displayId Parsing Rejects Numeric Values

**Date:** 2026-03-09
**Status:** Fixed

## Description of the Issue

When JSON like `{"displayId": 42}` is passed through JSONSerialization or MCP tool call arguments, numeric values may arrive as `Double` (NSNumber) rather than `Int`. Code paths using `as? Int` silently fail, causing valid requests to be rejected with "INVALID_INPUT" or "Provide either displayId or taskId" errors.

**Reproduction steps:**
1. Send `{"displayId": 42, "status": "planning"}` via MCP `update_task_status` tool
2. The `displayId` value arrives as `Double(42.0)` in the arguments dictionary
3. `args["displayId"] as? Int` returns `nil`, falling through to the error case

**Impact:** All MCP tool calls and some App Intent calls that use `displayId` or `milestoneDisplayId` as task/milestone identifiers could fail silently when the value comes through as a numeric type other than `Int`.

## Investigation Summary

Systematic review of all `displayId` and `milestoneDisplayId` parsing across the codebase.

- **Symptoms examined:** MCP tool calls with numeric displayId values rejected
- **Code inspected:** IntentHelpers.swift, UpdateStatusIntent.swift, MCPToolHandler.swift, CreateTaskIntent.swift, DeleteMilestoneIntent.swift, QueryMilestonesIntent.swift, UpdateTaskIntent.swift
- **Hypotheses tested:** NSNumber/Double bridging inconsistency with `as? Int` cast

## Discovered Root Cause

All `displayId` and `milestoneDisplayId` fields parsed from `[String: Any]` dictionaries use `as? Int`, which fails when JSONSerialization or MCP argument passing delivers the value as `Double`/`NSNumber`.

**Defect type:** Missing type coercion

**Why it occurred:** JSONSerialization deserializes JSON numbers as NSNumber. When bridged to Swift, whether this becomes `Int` or `Double` depends on the internal representation. MCP tool arguments always deliver numbers as `Double`. The original code assumed `as? Int` would always work for integer JSON values.

**Contributing factors:** Some code paths (e.g., `IntentHelpers.resolveMilestone`, `DeleteMilestoneIntent`, `QueryMilestonesIntent`, `CreateTaskIntent.resolveMilestone`) already had the `Double` fallback, showing awareness of the issue. But the fix was applied inconsistently.

## Resolution for the Issue

**Changes made:**
- `IntentHelpers.swift` — Added `parseIntValue(_:)` helper that accepts `Int`, `Double` (via `Int(exactly:)`), and `NSNumber`
- `IntentHelpers.swift` — Updated `resolveTask(from:taskService:)` to use `parseIntValue`
- `IntentHelpers.swift` — Updated `assignMilestone(from:to:milestoneService:)` to use `parseIntValue`
- `UpdateStatusIntent.swift` — Updated `execute(input:taskService:)` to use `IntentHelpers.parseIntValue`
- `MCPToolHandler.swift` — Updated `resolveTask(from:)`, `resolveMilestone(from:)`, `handleQueryTasks`, `handleQueryMilestones`, `handleCreateTask`, `handleUpdateTask` to use `IntentHelpers.parseIntValue`

**Approach rationale:** Centralising the coercion in a single `parseIntValue` helper ensures consistency and prevents future occurrences. Using `Int(exactly:)` for `Double` values rejects non-integral values like `42.5`.

**Alternatives considered:**
- Fixing each site individually with inline `as? Double` fallback — rejected because it's repetitive and error-prone

## Regression Test

**Test file:** `Transit/TransitTests/NumericDisplayIdParsingTests.swift`
**Test names:** `NumericDisplayIdParsingTests` (3 tests) and `NumericDisplayIdMCPTests` (6 tests)

**What it verifies:** That numeric `displayId` and `milestoneDisplayId` values (passed as `Double`) are accepted in all intent and MCP code paths.

**Run command:** `make test-quick` or target `TransitTests/NumericDisplayIdParsingTests` and `TransitTests/NumericDisplayIdMCPTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/IntentHelpers.swift` | Added `parseIntValue`, updated `resolveTask` and `assignMilestone` |
| `Transit/Transit/Intents/UpdateStatusIntent.swift` | Use `parseIntValue` for displayId |
| `Transit/Transit/MCP/MCPToolHandler.swift` | Use `parseIntValue` in 6 locations |
| `Transit/TransitTests/NumericDisplayIdParsingTests.swift` | New regression tests |
| `Transit/TransitTests/DashboardShortcutTests.swift` | Fix pre-existing compile error (nil -> "") |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- Always use `IntentHelpers.parseIntValue` when extracting integer values from `[String: Any]` dictionaries
- Never use bare `as? Int` for JSON-deserialized or MCP argument values

## Related

- Transit ticket: T-370
