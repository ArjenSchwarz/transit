# Bugfix Report: Reject Non-String Project In UpdateMilestoneIntent Name Lookup

**Date:** 2026-06-22
**Status:** Fixed

## Description of the Issue

When updating a milestone by name via `UpdateMilestoneIntent` (and the MCP `update_milestone` tool, which shares the same resolution path), a payload that supplies `project` as a non-string value was treated as if `project` were absent.

`IntentHelpers.resolveMilestoneByName` validated a malformed `projectId` but read `project` with `json["project"] as? String` without first checking presence/type. A non-string `project` therefore coerced to `nil`, and with no `projectId` either, `ProjectService.findProject(id: nil, name: nil)` returned `.noIdentifier`. The caller received the generic `INVALID_INPUT` / "Either projectId or project name is required" message instead of the field-specific `project must be a string` hint used by every related path.

**Reproduction steps:**
1. Have a project "Alpha" with a milestone "v1.0".
2. Call `UpdateMilestoneIntent.execute` with `{"name":"v1.0","project":123,"status":"done"}`.
3. Observe the error hint is "Either projectId or project name is required" rather than "project must be a string".

**Impact:** Low severity, correctness/usability. No data corruption — the milestone is correctly left untouched. The defect produced a misleading error hint for CLI/agent callers, making a type mistake in the `project` field look like a missing-identifier problem.

## Investigation Summary

- **Symptoms examined:** A non-string `project` field surfaced the generic no-identifier error instead of a field-specific type error, diverging from sibling fields.
- **Code inspected:** `IntentHelpers.resolveMilestoneByName` (the `project` read), `resolveMilestone` (the `name` guard added by T-1572), `validateUUIDField` (the `projectId` guard from T-753), and `ProjectService.findProject` (returns `.noIdentifier` when both id and name are nil).
- **Hypotheses tested:** Confirmed via the new regression test that the pre-fix path returns `INVALID_INPUT` with the wrong hint and that the milestone is not modified — so the only defect is the missing presence-vs-type guard, not a fallthrough mutation.

## Discovered Root Cause

`resolveMilestoneByName` used `json["project"] as? String`, which conflates "absent" with "present but not a string". A present non-string value silently became `nil` before `findProject` was called.

**Defect type:** Missing input validation (presence-vs-validity gap).

**Why it occurred:** The function already distinguished presence from validity for `projectId` (via `validateUUIDField`), but the `project` name field was added with a bare optional cast that loses the present-but-wrong-type case.

**Contributing factors:** The same presence-vs-validity pattern was applied to `milestoneId`/`projectId` (T-753), to project name filters (T-1116), to creation paths (T-1453), and to the `name` identifier in the sibling `resolveMilestone` dispatcher (T-1572), but this specific `project` read in `resolveMilestoneByName` was not covered by any of them.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Intents/IntentHelpers.swift` - In `resolveMilestoneByName`, after validating `projectId`, reject a present non-string `project` when `projectId` is nil, returning `.invalidInput(hint: "project must be a string")` before calling `findProject`.

**Approach rationale:** Mirrors the established presence-vs-validity guard used for `name` in `resolveMilestone` (T-1572) and for identifiers via `validateUUIDField` (T-753). The guard is scoped to `projectId == nil` so that a valid `projectId` still takes precedence and an irrelevant malformed `project` value alongside a good `projectId` does not block the lookup (consistent with how `findProject` prioritises id over name).

**Alternatives considered:**
- Reject a non-string `project` unconditionally (even when a valid `projectId` is present) - Not chosen: `findProject` ignores the name when an id is supplied, so blocking on an irrelevant field would be stricter than the established id-takes-precedence behaviour.

## Regression Test

**Test file:** `Transit/TransitTests/UpdateMilestoneIdentifierValidationTests.swift`
**Test name:** `nonStringProjectRejectsInsteadOfFallingBack`

**What it verifies:** A `{"name":"v1.0","project":123,"status":"done"}` payload returns `INVALID_INPUT` with a hint containing `project must be a string`, and the milestone status is unchanged (no update applied via the project-name fallback).

**Run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -only-testing:TransitTests/UpdateMilestoneIdentifierValidationTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Intents/IntentHelpers.swift` | Added present-non-string `project` guard in `resolveMilestoneByName` |
| `Transit/TransitTests/UpdateMilestoneIdentifierValidationTests.swift` | Added regression test `nonStringProjectRejectsInsteadOfFallingBack` |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (`make test-quick`)
- [x] Linters/validators pass (`make lint`)

**Manual verification:**
- Confirmed the test fails (wrong hint) before the fix and passes after, with all sibling tests unaffected.

## Prevention

**Recommendations to avoid similar bugs:**
- When a JSON field is meaningful, prefer a presence-then-type check (`if let raw = json[key], !(raw is Expected)`) over a bare `as? Expected`, which silently conflates absent with wrong-type.
- Keep parallel JSON fields (identifiers and their name counterparts) consistent: when one gains a presence-vs-validity guard, audit the siblings on the same path.

## Related

- T-1592 (this fix)
- T-1572 - Reject non-string `name` identifier in `UpdateMilestoneIntent` (sibling, same file)
- T-753 - Malformed `milestoneId`/`projectId` validation for `UpdateMilestoneIntent`
- T-1116 - Non-string project name filters
- T-1453 - Non-string project fields in creation paths
