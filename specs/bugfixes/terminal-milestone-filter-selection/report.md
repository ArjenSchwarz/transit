# Bugfix Report: Terminal milestone selections disappear from filter menu

**Date:** 2026-08-05
**Status:** Fixed

## Description of the Issue

A selected dashboard milestone disappeared from `MilestoneFilterMenu` after it transitioned to Done or Abandoned. Its UUID remained in the active filter, so its tasks continued to filter the dashboard, but the user could neither see the selected milestone nor deselect it individually.

**Reproduction steps:**
1. Select an open milestone from the dashboard filter.
2. Change that milestone to Done or Abandoned through Settings, MCP, or a synced device.
3. Reopen the dashboard milestone filter.

**Impact:** The filter count reported a selection that no longer had a visible menu row. Users could only clear every milestone filter at once.

## Investigation Summary

- **Symptoms examined:** A non-zero filter badge persisted while the corresponding terminal milestone row vanished.
- **Code inspected:** `MilestoneFilterMenu`, `MilestoneService.milestonesForProject`, dashboard filter tests, UI-test scenario support, and the milestone design specification.
- **Hypotheses tested:** Confirmed the problem was local to the dashboard menu: it requested `.open` milestones only. Add Task independently remains open-only by design and was not changed.

## Discovered Root Cause

`MilestoneFilterMenu.availableMilestones` populated its rows solely from open milestones. `selectedMilestones` is UUID state that is intentionally retained across a milestone status transition, but the menu made no union with selected accessible milestones.

**Defect type:** Logic error / stale selection state

**Why it occurred:** The menu applied the normal open-only choice rule to existing selections, even though terminal selections must remain available for removal.

**Contributing factors:** The selection-list construction had no pure ordering/deduplication helper or transition regression.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/Dashboard/MilestoneFilterMenu.swift` - Fetches all accessible milestones within the current project scope, retains the existing open-milestone order, then appends selected accessible records once by UUID. Terminal rows are struck through, show a Done or Abandoned label/icon, and expose their state and selection through accessibility.
- `Transit/TransitTests/MilestoneFilterMenuTests.swift` - Adds pure UUID-union coverage and a scoped Done/Abandoned transition regression. Also verifies that inaccessible/deleted selections retain the menu so Clear remains available.

**Approach rationale:** The dashboard now exposes only the normal open choices plus selected records the user can still act on. It preserves project filtering and does not broaden Add Task or task-edit creation behavior to terminal milestones.

**Alternatives considered:**
- Show every terminal milestone in the dashboard filter - rejected because it unnecessarily expands normal options and conflicts with the open-only default.
- Clear terminal selections automatically - rejected because it silently changes an active dashboard filter and prevents deliberate deselection.

## Regression Test

**Test file:** `Transit/TransitTests/MilestoneFilterMenuTests.swift`
**Test names:** `visibleMilestoneIDsPreservesOpenOrderAndDeduplicatesSelectedMilestones`, `availableMilestonesKeepsSelectedTerminalMilestonesWithinSelectedProjects`

**What it verifies:** Open rows retain their order, selected Done and Abandoned milestones within the active project scope remain visible exactly once, and selected milestones outside that scope are not exposed.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Dashboard/MilestoneFilterMenu.swift` | Union selected accessible milestones with open options; distinguish terminal rows visually and through accessibility. |
| `Transit/TransitTests/MilestoneFilterMenuTests.swift` | Add pure union, status-transition, scope, duplicate, and inaccessible-selection regressions. |
| `CHANGELOG.md` | Record the user-visible dashboard filter fix. |

## Verification

**Automated:**
- [x] Regression tests pass.
- [x] macOS unit suite passes (`make test-quick`).
- [x] Linter passes (`make lint`).
- [x] iOS app build passes (`make build-ios`).
- [ ] `make test` and `make test-ui` are blocked before tests start by the pre-existing `Cannot find 'MCPTestHelpers' in scope` errors in `TransitTests/ProjectLookupStorageFailureSurfaceTests.swift` (lines 81, 84, 88, 92, 96, and 102-109).

**Manual verification:**
- Confirmed the unit transition covers both Done and Abandoned states, preserves the service-provided scoped order, excludes selected milestones in another project, and keeps Clear reachable for a deleted/unavailable UUID.
- UI automation was not added: reproducing the runtime transition would require a brittle Settings round trip while retaining dashboard-local `@State`, or production test-state injection. The deterministic unit transition covers the menu's data contract directly.

## Prevention

- Keep selection-list construction in pure helpers that explicitly union normal options and current accessible selections.
- Add state-transition coverage whenever an active selection may become invalid for new choices.
- Keep creation flows such as Add Task separate from edit/filter flows that must preserve existing terminal state.

## Related

- Transit ticket `T-1825`
- `specs/milestones/design.md` section 5.1
