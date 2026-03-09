# Bugfix Report: Milestone Description Cannot Be Cleared

**Date:** 2026-03-09
**Status:** Fixed

## Description of the Issue

When editing a milestone and clearing its description field, the description is not removed. The milestone retains its original description after saving.

**Reproduction steps:**
1. Create a milestone with a description
2. Edit the milestone and clear the description field
3. Save the milestone
4. Observe the description is still present

**Impact:** Users cannot remove a milestone's description once set. Low severity but frustrating UX.

## Investigation Summary

The bug was in the interaction between `MilestoneEditView` and `MilestoneService.updateMilestone()`.

- **Symptoms examined:** Description field cleared in UI but not persisted
- **Code inspected:** `MilestoneEditView.save()`, `MilestoneService.updateMilestone()`
- **Hypotheses tested:** Confirmed the service method ignores `nil` description values

## Discovered Root Cause

`MilestoneService.updateMilestone()` uses `if let description` to gate the description update. When the user clears the description, the view passes `nil` (since the trimmed string is empty). The service interprets `nil` as "no change requested" and skips the update entirely.

**Defect type:** Logic error — ambiguous use of `nil` (meaning both "no change" and "clear value")

**Why it occurred:** The `description` parameter serves double duty: `nil` means "don't change" for callers like the intent system (where the field may not be provided), but the view also uses `nil` to mean "clear the value".

**Contributing factors:** The same pattern works correctly for `name` because an empty name is invalid, so there's no need to distinguish "not provided" from "cleared".

## Resolution for the Issue

**Changes made:**
- `Transit/Services/MilestoneService.swift` — Added `clearDescription: Bool = false` parameter to `updateMilestone()`. When `description` is `nil` and `clearDescription` is `true`, the milestone's description is set to `nil`.
- `Transit/Views/Settings/MilestoneEditView.swift` — Pass `clearDescription: trimmedDesc.isEmpty` when calling `updateMilestone()`.

**Approach rationale:** The `clearDescription` flag explicitly disambiguates "no change" (`nil`, `false`) from "clear the value" (`nil`, `true`). The default value of `false` preserves backward compatibility for all existing callers (intents, tests).

**Alternatives considered:**
- Making `description` non-optional and always applying it — breaks intent callers that omit the field
- Using a sentinel empty string `""` — semantically unclear, mixes concerns

## Regression Test

**Test file:** `Transit/TransitTests/MilestoneServiceTests.swift`
**Test name:** `updateMilestoneClearsDescriptionWithFlag`

**What it verifies:** That passing `nil` without `clearDescription` preserves the existing description, and passing `clearDescription: true` sets the description to `nil`.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Services/MilestoneService.swift` | Added `clearDescription` parameter to `updateMilestone()` |
| `Transit/Transit/Views/Settings/MilestoneEditView.swift` | Pass `clearDescription` flag when saving |
| `Transit/TransitTests/MilestoneServiceTests.swift` | Added regression test |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters/validators pass

## Prevention

**Recommendations to avoid similar bugs:**
- When using optional parameters for "update if provided" semantics, consider whether `nil` can legitimately mean "clear the value" and handle that case explicitly
- Test clearing/unsetting of optional fields, not just setting them
