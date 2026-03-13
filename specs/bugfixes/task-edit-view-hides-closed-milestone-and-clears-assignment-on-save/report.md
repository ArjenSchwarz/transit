# Bugfix Report: TaskEditView hides closed milestone and clears assignment on save

**Date:** 2026-03-13
**Status:** Fixed

## Description of the Issue

When a task already assigned to a done or abandoned milestone was opened in `TaskEditView`, the milestone picker only rendered open milestones. The existing non-open milestone had no matching picker option, so the assignment disappeared from the UI and could be cleared on save.

**Reproduction steps:**
1. Create a task with a milestone in a project.
2. Move that milestone to Done or Abandoned.
3. Open the task in `TaskEditView` and save without intentionally changing the milestone.

**Impact:** Editing a task could silently unassign a closed milestone, causing accidental data loss in milestone tracking.

## Investigation Summary

Used a structured inspection of the edit view’s milestone selection flow, then reproduced the defect with a focused regression test.

- **Symptoms examined:** Closed milestone assignment was missing from the edit picker and could be lost after save.
- **Code inspected:** `Transit/Transit/Views/TaskDetail/TaskEditView.swift`, `Transit/Transit/Services/MilestoneService.swift`, and existing milestone lookup tests.
- **Hypotheses tested:** Confirmed the issue was not in assignment validation; the view filtered picker options to `.open` only, excluding the current closed selection from the picker tags.

## Discovered Root Cause

`TaskEditView` populated its milestone picker with open milestones only, even during edit. When the task’s current milestone was done or abandoned, the picker had no option corresponding to the bound `selectedMilestone`.

**Defect type:** Logic error

**Why it occurred:** The add-task flow and edit-task flow shared the same open-only milestone filtering assumption, but the edit flow must preserve the current assignment even when it is no longer open.

**Contributing factors:** Picker options were computed inline in the view, so there was no explicit test covering the “include current closed selection” case.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/TaskDetail/TaskEditView.swift:28-33,118-123,206-212,271-287` - Replaced the open-only picker source with a shared helper that keeps the task’s currently selected milestone available during edit when it belongs to the same project.
- `Transit/TransitTests/TaskEditViewMilestoneTests.swift:22-75` - Added regression coverage for including a selected closed milestone, avoiding duplicate open milestones, and excluding milestones from other projects.

**Approach rationale:** Preserve the current assignment without broadening the picker to every closed milestone in the project. This fixes the data-loss path while keeping the edit UI focused on open milestones plus the existing selection.

**Alternatives considered:**
- Show all milestones during edit - workable, but broader than necessary when the only required behaviour is preserving the current assignment.

## Regression Test

**Test file:** `Transit/TransitTests/TaskEditViewMilestoneTests.swift`
**Test name:** `availableMilestonesIncludesSelectedClosedMilestone`

**What it verifies:** The task edit milestone picker includes the currently selected closed milestone alongside open milestones for the same project.

**Run command:** `xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=macOS' -configuration Debug -derivedDataPath ./DerivedData -only-testing:TransitTests/TaskEditViewMilestoneTests`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/TaskDetail/TaskEditView.swift` | Keeps the current closed milestone available in the edit picker while still filtering new choices to open milestones. |
| `Transit/TransitTests/TaskEditViewMilestoneTests.swift` | Adds regression coverage for preserving a closed selected milestone in the picker. |

## Verification

**Automated:**
- [x] Regression test passes
- [x] macOS unit suite passes (`make test-quick`)
- [x] iOS regression test passes (`xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug -derivedDataPath ./DerivedData -only-testing:TransitTests/TaskEditViewMilestoneTests | xcbeautify`)
- [ ] Linters/validators pass (`make lint` still fails on the pre-existing `type_body_length` violation in `Transit/TransitTests/TaskEditSaveErrorTests.swift`)

**Manual verification:**
- Reproduced the bug with a focused failing regression test before implementation.
- Confirmed the fix keeps edit-only closed assignments selectable without exposing closed milestones from other projects.

## Prevention

**Recommendations to avoid similar bugs:**
- Extract view selection lists into small testable helpers when edit behaviour differs from creation behaviour.
- Add regression tests for edit flows that must preserve existing values no longer allowed for new records.
- Review picker option filtering whenever model state can move into terminal statuses.

## Related

- Transit ticket `T-415`
