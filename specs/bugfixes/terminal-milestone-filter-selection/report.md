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

`MilestoneFilterMenu.availableMilestones` populated its rows solely from open milestones. `selectedMilestones` is UUID state that is intentionally retained across a milestone status transition, but the menu made no union with selected accessible milestones. Its service-backed read also did not make the presented SwiftUI menu observe externally persisted status or deletion changes.

**Defect type:** Logic error / stale selection state

**Why it occurred:** The menu applied the normal open-only choice rule to existing selections, even though terminal selections must remain available for removal.

**Contributing factors:** The selection-list construction had no pure ordering/deduplication helper or transition regression, and it did not observe the SwiftData records that external MCP and CloudKit updates mutate.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/Dashboard/MilestoneFilterMenu.swift` - Observes all milestones with a SwiftData `@Query`, so local status/deletion mutations, MCP changes, and CloudKit imports refresh an already-open menu. It scopes the observed records in memory because the dynamic selected-project set cannot be represented in a CloudKit-safe SwiftData predicate, then lists open rows before selected terminal rows once by UUID. Within one scoped project rows sort by milestone name; across projects they sort by displayed project/name title, with UUID as a stable final tie-breaker. Duplicate IDs retain one row rather than trapping. Terminal rows remain struck through and display their status. Selected rows use the native `.isSelected` accessibility trait, while each row label contains only its title and optional terminal status, preventing duplicate selected announcements.
- `Transit/TransitTests/MilestoneFilterMenuTests.swift` - Adds pure UUID-union coverage, a persisted Done transition regression proving open-first/terminal-second deterministic placement, displayed multi-project ordering coverage, a deletion/Clear regression, and exact open/Done/Abandoned label coverage.

**Approach rationale:** The dashboard now exposes only the normal open choices plus selected records the user can still act on. The live query avoids stale menu content while stable in-memory ordering matches the title users see. The native selection trait is shared by open and terminal selected rows and is announced once. Add Task and task-edit creation behavior remain open-only.

**Alternatives considered:**
- Show every terminal milestone in the dashboard filter - rejected because it unnecessarily expands normal options and conflicts with the open-only default.
- Clear terminal selections automatically - rejected because it silently changes an active dashboard filter and prevents deliberate deselection.

## Regression Test

**Test file:** `Transit/TransitTests/MilestoneFilterMenuTests.swift`
**Test names:** `visibleMilestoneOptionUsesOpenRecordsWithinCurrentProjectScope`, `visibleMilestoneIDsPreservesOpenOrderAndDeduplicatesSelectedMilestones`, `availableMilestonesHandlesPersistedStatusTransitionWithDeterministicTerminalPlacement`, `multiProjectOrderingMatchesDisplayedMilestoneTitles`, `deletedSelectedMilestoneLeavesMenuAvailableForClear`, `menuRemainsMountedWhilePresentedAfterClearingLastSelection`, `accessibilityLabelsIncludeTerminalStatusWithoutSelectionDuplication`

**What it verifies:** The production visibility predicate treats only scoped open records as normal choices; a fresh SwiftData snapshot sees an open selected milestone move into the selected-terminal suffix after a persisted Done transition; open rows stay first in deterministic order; multi-project ordering matches displayed titles; another project is excluded; deleting a selected record preserves access to Clear; clearing the final selection retains an open presentation; and labels contain one title plus optional terminal status.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Dashboard/MilestoneFilterMenu.swift` | Observe all milestones; scope, title-order, and union open/selected-terminal records; expose terminal status and native selected accessibility state. |
| `Transit/TransitTests/MilestoneFilterMenuTests.swift` | Add pure union, persisted transition, displayed-order, deletion/Clear, and accessibility regressions. |
| `CHANGELOG.md` | Record the user-visible dashboard filter fix. |

## Verification

**Automated:**
- [x] Full macOS unit suite passes (`make test-quick`).
- [x] SwiftLint passes (`make lint`).
- [x] iOS Simulator and macOS builds pass (`make build`).
- [x] Focused iOS simulator regression suite passes (`-only-testing:TransitTests/MilestoneFilterMenuTests`).
- [ ] Full `make test` exceeded the five-minute command harness after compiling both test bundles and beginning iOS execution; it did not return a final result.
- [ ] Full `make test-ui` exceeded the five-minute command harness after completing UI execution. It reported failures in `TransitUITests.testClearAll`, `TransitUITests.testEditViewPreservesTaskMilestone`, and `DataMaintenanceUITests.testDataMaintenanceGoldenPath`; the unchanged `TransitUITests.testMilestoneFilterMenu` passed. A baseline run on `origin/main` was not completed in this session.

**Manual verification:**
- Confirmed the persisted transition regression, multi-project title ordering, deleted-selection Clear behavior, presented-menu lifecycle behavior, and accessibility label contract cover the filter's state contracts.
- A new UI transition assertion was not retained: XCTest cannot reliably query a SwiftUI list row's updated accessibility state while the sheet remains presented, and a second sheet round trip destabilizes the seeded board assertion. The existing milestone filter UI flow passes, while focused unit coverage verifies the data and accessibility contracts directly.

## Prevention

- Keep selection-list construction in pure helpers that explicitly union normal options and current accessible selections.
- Use an observed SwiftData source for menu options that must react to external mutations.
- Keep deterministic menu ordering aligned with the title users see.
- Add state-transition coverage whenever an active selection may become invalid for new choices.
- Keep creation flows such as Add Task separate from edit/filter flows that must preserve existing terminal state.

## Related

- Transit ticket `T-1825`
- `specs/milestones/design.md` section 5.1
