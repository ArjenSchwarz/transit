# Bugfix Report: Reject Fractional Milestone DisplayId

**Date:** 2026-03-09
**Status:** Fixed

## Description of the Issue

When a fractional number (e.g., `1.9`) was passed as `displayId` in milestone intent lookups, it was silently truncated to an integer (e.g., `1`) instead of being rejected. This could cause operations to target the wrong milestone.

**Reproduction steps:**
1. Create a milestone with displayId 1
2. Call UpdateMilestoneIntent or DeleteMilestoneIntent with `{"displayId": 1.9, ...}`
3. Observe that the operation targets milestone with displayId 1 instead of returning an error

**Impact:** Medium severity — could cause unintended milestone updates or deletions when non-integer values are passed, particularly from programmatic callers or malformed input.

## Investigation Summary

- **Symptoms examined:** Fractional displayId values silently resolve to the wrong milestone
- **Code inspected:** `IntentHelpers.resolveMilestone`, `DeleteMilestoneIntent.execute`, `CreateTaskIntent.resolveMilestone`, `MCPToolHandler.resolveMilestone`
- **Hypotheses tested:** Confirmed that `Int.init(_: Double)` truncates rather than rejecting non-integer values

## Discovered Root Cause

Two locations use `Int.init(_: Double)` to convert JSON-parsed Double values to Int for displayId lookup. This initializer truncates fractional values (e.g., `Int(1.9)` returns `1`) instead of rejecting them.

**Defect type:** Missing validation

**Why it occurred:** `Int.init(_: Double)` was used instead of `Int(exactly:)`. The `CreateTaskIntent` was already fixed to use `Int(exactly:)` but the fix was not applied to the other two locations.

**Contributing factors:** JSON numbers are parsed as `Double` by `JSONSerialization`, requiring an explicit Double-to-Int conversion step that needs careful handling.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/IntentHelpers.swift:92` — Changed `.map(Int.init)` to `.flatMap({ Int(exactly: $0) })`
- `Transit/Transit/Intents/DeleteMilestoneIntent.swift:55-56` — Changed `Int(doubleVal)` to `Int(exactly: doubleVal)` with guard

**Approach rationale:** `Int(exactly:)` returns `nil` when the Double value is not exactly representable as an Int, causing the guard to fail and return an `INVALID_INPUT` error. Whole-number doubles (e.g., `1.0`) still convert successfully.

**Alternatives considered:**
- Floor/ceil rounding — Rejected because it still silently changes the input value
- String-based validation — Rejected because the value is already parsed from JSON as a number

## Regression Test

**Test files:**
- `Transit/TransitTests/UpdateMilestoneIntentTests.swift`
- `Transit/TransitTests/DeleteMilestoneIntentTests.swift`

**Test names:** `fractionalDisplayIdReturnsInvalidInput`, `wholeNumberDoubleDisplayIdSucceeds`

**What they verify:** Fractional displayId values (e.g., `1.9`) return `INVALID_INPUT` error, while whole-number doubles (e.g., `1.0`) still resolve successfully.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/IntentHelpers.swift` | Use `Int(exactly:)` instead of `Int.init` for Double-to-Int conversion |
| `Transit/Transit/Intents/DeleteMilestoneIntent.swift` | Use `Int(exactly:)` instead of `Int.init` for Double-to-Int conversion |
| `Transit/TransitTests/UpdateMilestoneIntentTests.swift` | Add regression tests for fractional and whole-number displayId |
| `Transit/TransitTests/DeleteMilestoneIntentTests.swift` | Add regression tests for fractional and whole-number displayId |
| `Transit/TransitTests/DashboardShortcutTests.swift` | Fix pre-existing compilation error (nil for non-optional String parameter) |

## Verification

**Automated:**
- [x] Regression tests pass
- [x] Full test suite passes (one pre-existing failure unrelated to this change)
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- Always use `Int(exactly:)` when converting from `Double` to `Int` for identifier lookups
- When fixing a pattern in one location, search for the same pattern elsewhere in the codebase

## Related

- Transit ticket: T-349
