# Bugfix Report: iPad Filter Projects Missing

**Date:** 2026-02-11
**Status:** Fixed

## Description of the Issue

On iPad, tapping the filter button in the dashboard toolbar shows a popover that contains only a checkmark (the "Done" toolbar button) with no project names listed. The filter works correctly on both iPhone and Mac.

**Reproduction steps:**
1. Open Transit on an iPad (or iPad simulator)
2. Ensure at least one project with tasks exists
3. Tap the filter button in the dashboard toolbar
4. Observe: only the navigation bar with a checkmark ("Done" button) is visible; no project rows appear

**Impact:** Medium — iPad users cannot filter the kanban board by project, making multi-project workflows unusable on iPad.

## Investigation Summary

Traced the filter presentation chain from `DashboardView.filterButton` through `FilterPopoverView` to understand platform-specific rendering differences.

- **Symptoms examined:** Filter popover on iPad shows navigation bar but no List content; identical code works on iPhone and Mac
- **Code inspected:** `DashboardView.swift` (popover presentation), `FilterPopoverView.swift` (popover content and sizing), `ProjectColorDot.swift` (row component)
- **Hypotheses tested:**
  - ProjectColorDot rendering issue → Ruled out (simple 12x12 rectangle, no platform dependency)
  - SwiftData query issue → Ruled out (same `@Query` works on all platforms)
  - Platform-specific popover sizing → **Confirmed as root cause**

## Discovered Root Cause

`FilterPopoverView` uses `.frame(minWidth: 200)` with no height constraint. The `.presentationDetents([.medium, .large])` modifiers are **sheet-only** — they are silently ignored when the content is presented as a popover.

**Defect type:** Missing layout constraint for platform-specific presentation

**Why it occurred:**

1. `DashboardView.swift:103` presents `FilterPopoverView` via `.popover(isPresented:)`
2. On **iPhone**, SwiftUI automatically converts `.popover` to a `.sheet` — the `presentationDetents` kick in and give the sheet proper height. Projects display correctly.
3. On **Mac**, popovers natively size themselves based on content intrinsic size. Projects display correctly.
4. On **iPad**, `.popover` stays as an actual popover. The `presentationDetents` and `presentationDragIndicator` modifiers are ignored. With only `minWidth: 200` and no height hint, the `NavigationStack` + `List` flexible content collapses to zero height — showing only the navigation bar (with the "Done" checkmark button) and no content area for project rows.

**Contributing factors:**
- Development and testing primarily done on iPhone simulator where the bug doesn't manifest
- SwiftUI silently ignores inapplicable presentation modifiers rather than warning
- The existing UI test (`testTappingFilterButtonShowsPopover`) runs on iPhone simulator, masking the iPad-specific failure

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/Dashboard/FilterPopoverView.swift:51` — Added `minHeight: 300` to the frame modifier so the popover has sufficient height on iPad to display project rows

**Approach rationale:** Adding `minHeight` to the existing `.frame()` modifier is the minimal, targeted fix. On iPhone (where popover converts to sheet), `presentationDetents` overrides this. On Mac, the popover already sizes correctly and `minHeight` acts as a safety floor. On iPad, this gives the popover the height it needs to display the List content.

**Alternatives considered:**
- Using `.presentationSizing(.fitted)` — Would be more semantic but doesn't reliably size `List` content in popovers
- Removing `NavigationStack` wrapper for popovers — Would fix sizing but loses the inline title and toolbar button styling
- Switching from `.popover` to `.sheet` on iPad — Would work but popovers are the expected iPad pattern per HIG

## Regression Test

**Test file:** `Transit/TransitUITests/TransitUITests.swift`
**Test name:** `testTappingFilterButtonShowsPopover` (line 104)

**What it verifies:** After tapping the filter button, asserts that a project name ("Alpha") appears in the popover. This test already exists and passes on iPhone; running it on an iPad simulator destination will verify the fix.

**Run command:**
```bash
xcodebuild test -project Transit/Transit.xcodeproj -scheme Transit \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  -only-testing:TransitUITests/TransitUITests/testTappingFilterButtonShowsPopover test
```

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Dashboard/FilterPopoverView.swift` | Added `minHeight: 300` to `.frame()` for iPad popover sizing |

## Verification

**Automated:**
- [ ] Regression test passes (requires iPad simulator — not available in current CI environment)
- [ ] Full test suite passes (requires Xcode)
- [ ] Linters/validators pass (requires SwiftLint)

**Manual verification:**
- Build and run on iPad simulator or device
- Tap filter button → popover should show project names with color dots
- Verify iPhone and Mac behavior remain unchanged

## Prevention

**Recommendations to avoid similar bugs:**
- Add iPad simulator destinations to CI test matrix for UI tests
- When using `.popover`, always provide both width and height constraints — `.presentationDetents` only applies to sheets
- Consider a lint rule or code review checklist item for popover sizing on iPad

## Related

- `DashboardView.swift:103` — Popover presentation site
- Existing UI test: `TransitUITests/testTappingFilterButtonShowsPopover`
