# Bugfix Report: Reject Non-String MCP milestoneId Values

**Date:** 2026-05-02
**Status:** Fixed

## Description of the Issue

`MCPToolHandler.resolveMilestone(from:)` validates malformed `milestoneId`
strings (T-769), but only enters that branch when `args["milestoneId"]` is a
`String`. If `milestoneId` is present with another type — a number, boolean,
array, etc. — the cast `args["milestoneId"] as? String` fails and the resolver
falls through to the generic
`Provide either displayId (integer) or milestoneId (UUID string)` error.

This violates the project's rule (validation.md) that identifier keys must be
validated separately from presence: a key that is present but malformed must
be rejected with a key-specific error rather than treated as missing.

**Reproduction steps:**
1. Call MCP `update_milestone` with arguments `{"milestoneId": 42, "name": "v2.0"}`.
2. Observe the response error reads
   `Provide either displayId (integer) or milestoneId (UUID string)` instead of
   `milestoneId must be a valid UUID string`.
3. Same problem on `delete_milestone` with `{"milestoneId": 42}`.

**Impact:** Low severity. The handler still returns an error (no silent
success or unintended write), but the error is misleading. An agent that has
already supplied a `milestoneId` may interpret the generic message as a hint
that the key is missing and retry with the same invalid value.

## Investigation Summary

- **Symptoms examined:** Error messages returned by `update_milestone` and
  `delete_milestone` when `milestoneId` is a JSON number or boolean.
- **Code inspected:** `MCPToolHandler.resolveMilestone(from:)`,
  `IntentHelpers.validateUUIDField(_:in:)` (the App Intent equivalent fixed in
  T-789/T-753), and the existing T-769 test cases that cover malformed string
  `milestoneId` values.
- **Hypotheses tested:** Whether the type-cast pattern silently drops
  non-string values — confirmed by adding parameterised tests that supply
  `Int` and `Bool` `milestoneId` arguments and observing the generic
  fall-through error.

## Discovered Root Cause

`resolveMilestone(from:)` uses `else if let idStr = args["milestoneId"] as? String`
which is a combined presence + type check. When the key exists but the value
is not a `String`, the optional cast returns `nil` and control flows to the
generic `Provide either…` error message, indistinguishable from the case where
neither identifier was supplied.

**Defect type:** Missing validation (presence/type conflation).

**Why it occurred:** T-769 added separate UUID-format validation for the
string case but kept the same combined `as? String` pattern, so non-string
inputs were never reached by the new validation.

**Contributing factors:** The same pattern caused T-789 in `DeleteMilestoneIntent`;
it was fixed there by routing through `IntentHelpers.validateUUIDField`. The
MCP handler does not use that helper and has its own resolver.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/MCP/MCPToolHandler.swift` — In `resolveMilestone(from:)`,
  gate the `milestoneId` branch on key presence (`args["milestoneId"] != nil`)
  rather than on the success of `as? String`. Inside that branch, cast to
  `String` and parse as `UUID` in a single guard that returns the existing
  `milestoneId must be a valid UUID string` error for any failure (non-string
  or malformed string).

**Approach rationale:** Mirrors the pattern T-769 established for malformed
string `milestoneId` values, the T-634 pattern for non-integer `displayId`,
and `IntentHelpers.validateUUIDField` on the App Intent side. Smallest
possible change; preserves the existing error message wording so agents and
tests already coded to it continue to work.

**Alternatives considered:**
- Refactor MCP handler to call `IntentHelpers.validateUUIDField` — cleaner
  long-term but a larger change and inconsistent with the surrounding
  resolver code that returns `Result<…, ResolveError>` rather than the
  intent error type. Out of scope for this fix.

## Regression Test

**Test file:** `Transit/TransitTests/MCPNonStringMilestoneIdTests.swift`

**Test names:**
- `updateMilestoneWithNumericMilestoneIdReturnsSpecificError`
- `deleteMilestoneWithNumericMilestoneIdReturnsSpecificError`
- `updateMilestoneWithBooleanMilestoneIdReturnsSpecificError`
- `deleteMilestoneWithBooleanMilestoneIdReturnsSpecificError`

**What they verify:** When `milestoneId` is a JSON `Int` or `Bool` rather than
a `String`, the MCP `update_milestone` and `delete_milestone` handlers reply
with `isError: true` and a message containing
`milestoneId must be a valid UUID`, not the generic fall-through message.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/MCP/MCPToolHandler.swift` | Split `milestoneId` presence/type check in `resolveMilestone(from:)`. |
| `Transit/TransitTests/MCPNonStringMilestoneIdTests.swift` | New file with four regression tests covering numeric and boolean `milestoneId` on `update_milestone` and `delete_milestone` (split out to avoid `type_body_length` violation in the existing display-id test struct). |

## Verification

**Automated:**
- [x] Regression tests pass
- [x] Full unit test suite (`make test-quick`) passes
- [x] `make lint` passes

## Prevention

**Recommendations to avoid similar bugs:**
- Always gate identifier validation on `args[key] != nil`, not on a combined
  `as? String` cast. The cast hides non-string inputs and reuses the
  "missing" code path.
- When adding format validation to an existing identifier branch, audit the
  type cast that guards the branch in the same change — otherwise the new
  validation is unreachable for one class of malformed input.

## Related

- T-769: Validate malformed string `milestoneId` in MCP milestone handlers (same
  resolver, string case).
- T-789: Reject malformed `milestoneId` UUIDs in `DeleteMilestoneIntent`
  (App Intent counterpart).
- T-634: Reject non-integer `displayId` in MCP handlers.
- T-665: Validate `projectId` UUID format in milestone queries.
