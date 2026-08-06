# Bugfix Report: iPhone Portrait Can Render a Multi-Column Dashboard

**Date:** 2026-08-02
**Status:** Superseded

> **Superseded 2026-08-06:** The product decision and requirement 13.1 were corrected to restore the original width-based behavior. Wide iPhone portrait layouts use the multi-column Kanban board when at least two 200-point columns fit; only narrower layouts use the segmented single-column fallback. The investigation below remains as historical context for PR #205.

## Description of the Issue

An iPhone portrait dashboard can render the multi-column kanban view when the compact-width window is at least 400 points wide. Requirement 13.1 requires every iPhone compact-width portrait layout to use the segmented single-column view, independent of that width.

**Reproduction steps:**
1. Launch Transit on an iPhone in portrait orientation with a compact-width window around 400 points or wider.
2. Open the dashboard.
3. Observe that the segmented status control is absent and multiple kanban columns are rendered.

**Impact:** The portrait iPhone layout violates the platform-adaptive dashboard contract and presents the wrong interaction model on affected device/window widths.

## Investigation Summary

The dashboard layout path was inspected from its root caller through both layout implementations and existing UI/unit coverage.

- **Symptoms examined:** Compact portrait widths below and above the 400-point geometry boundary; iPhone landscape; narrow iPad split view; regular iPad; Mac.
- **Code inspected:** `DashboardView`, `KanbanBoardView`, `SingleColumnView`, `ColumnView`, `TransitApp`, existing dashboard tests, and the iOS UI test launch helper.
- **Hypotheses tested:** The issue is not in the segmented control or column views; the root view selects `KanbanBoardView` before either child can affect layout. The existing drag/drop and filter callers remain downstream of this selection and do not alter it.

## Discovered Root Cause

`DashboardView` derives `rawColumnCount` only from `geometry.size.width / 200`. It uses `verticalSizeClass` only to cap landscape columns, and does not use compact `horizontalSizeClass` to force portrait into the segmented path. Therefore a compact-width portrait geometry of 400 points produces two columns.

**Defect type:** Layout-selection logic error and missing boundary condition.

**Why it occurred:** The original geometry rule treated width as sufficient to choose between one and multiple columns. That is valid for iPad and Mac, and the landscape cap is valid for iPhone landscape, but it does not encode the stronger requirement that compact-width portrait always uses one column.

**Five whys:**
1. Why can portrait show multiple columns? Because `rawColumnCount` becomes two or more at widths of 400 points and above.
2. Why is that raw count used in portrait? Because the selection code only branches on `isPhoneLandscape` and `columnCount == 1`.
3. Why does it not branch on portrait compact width? Because `horizontalSizeClass` is read but ignored by the selection calculation.
4. Why was the ignored size class not caught? Existing UI coverage allowed the segmented control to be absent, and unit coverage did not exercise the layout selector across the compact-width boundary.
5. Root cause: Device class and orientation were not represented as an explicit, testable layout-selection rule; width-only geometry leaked into the compact portrait path.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/Dashboard/DashboardLayout.swift` — Extracted the layout decision from `DashboardView` into a value-returning helper. A phone in compact width with regular height now returns `.singleColumn` before width-based column counting; iPad and Mac retain geometry-based adaptation and only fall back to `.singleColumn` when one 200pt column fits. Phone landscape, including regular-width compact-height phones, still caps geometry-derived columns at three.
- `Transit/Transit/Views/Dashboard/DashboardView.swift` — Supplies the iOS device idiom to the selector and uses the resulting layout mode to select `SingleColumnView` or `KanbanBoardView`, preserving the existing task tap, drop callbacks, and landscape initial scroll target.
- `Transit/TransitTests/DashboardLayoutTests.swift` — Added width-range and cross-platform regression tests for phone portrait, wide and narrow iPad split view, both phone landscape size-class shapes, iPad, Mac, and missing size classes.
- `Transit/TransitUITests/TransitUITests.swift` — Makes the portrait UI regression deterministic by setting portrait orientation and requiring the segmented control plus Active default instead of allowing the control to be absent.

**Approach rationale:** The selection rule is now explicit and unit-testable. The phone portrait rule combines device idiom with size classes, so it covers 400-point and wider compact phone windows without forcing wider iPad Split View panes into the segmented path. iPad and Mac continue to use geometry adaptation, with a single-column fallback only below the 200pt column-fit boundary. Keeping the existing child views and callbacks avoids changing dashboard behavior outside the selection boundary.

**Alternatives considered:**
- Lowering `columnMinWidth` or increasing it — rejected because any width threshold would remain device-specific and could regress iPad/Mac geometry adaptation.
- Checking only `horizontalSizeClass == .compact` — rejected because iPhone landscape and iPad Split View can also report compact width but must retain geometry-based adaptation.
- Using only `verticalSizeClass` for phone detection — rejected because iPad and other regular-height panes can share the same vertical class; the iOS device idiom is needed to distinguish phone portrait from iPad Split View.

## Regression Test

**Test file:** `Transit/TransitTests/DashboardLayoutTests.swift`
**Test names:** `compactPortraitUsesSingleColumnAtEveryWidth(width:)`, `compactWidthRegularHeightUsesGeometryAdaptationForWideIPadSplitView()`, `narrowIPadSplitViewFallsBackToSingleColumn()`, `compactHeightRetainsLandscapeGeometryAdaptation()`, `regularWidthCompactHeightRetainsPhoneLandscapeAdaptation()`, `regularIPadWidthRetainsGeometryAdaptation()`, `regularMacWidthRetainsGeometryAdaptationAndCapsAtFiveColumns()`, `missingSizeClassesRetainWidthBasedPreviewFallback()`, `missingVerticalSizeClassDoesNotAssumePortrait()`

**What it verifies:** Phone compact-width portrait uses one column across representative widths (320, 375, 390, 400, 428, and 599 points). Wide iPad Split View retains geometry-based multi-column adaptation, while a pane narrower than one 200pt column falls back to the segmented view. Phone landscape, including regular-width compact-height phones, retains its three-column cap and Planning initial target; regular iPad and Mac retain geometry adaptation. Missing size classes retain the width-based fallback used by previews and macOS, and the iOS UI test requires the segmented control and Active default rather than silently passing when the control is missing.

**Run command:** `make test-quick` and `make test-ui`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Dashboard/DashboardLayout.swift` | Extract current layout-selection result for focused tests. |
| `Transit/Transit/Views/Dashboard/DashboardView.swift` | Route the root layout choice through the extracted helper. |
| `Transit/TransitTests/DashboardLayoutTests.swift` | Add boundary and cross-platform regression coverage. |
| `Transit/TransitUITests/TransitUITests.swift` | Require the portrait segmented control and Active default. |
| `specs/bugfixes/iphone-portrait-can-render-a-multi-column-dashboard/report.md` | Record investigation and red-test checkpoint. |

## Verification

**Automated:**
- [x] Regression tests pass — `DashboardLayoutTests` passes on macOS and iOS, including compact portrait widths 320, 375, 390, 400, 428, and 599 points plus iPad split, landscape, iPad, Mac, and missing-size-class cases.
- [x] Portrait UI behavior passes in the full iOS run — `testIPhonePortraitDefaultsToActiveSegment` passed on the iPhone 17 iOS 26.5 Simulator, including the segmented-control and selected Active accessibility assertions.
- [~] Full iOS suite — `make test` result bundle `DerivedData/Logs/Test/Test-Transit-2026.08.02_12-09-36-+1000.xcresult` reports 1,161/1,164 tests passed. The only three failures exactly match the known iOS 26.5 baseline: `testClearAll` (`XCTAssertTrue failed`), `testEditViewPreservesTaskMilestone` (`XCTAssertTrue failed`), and `testDataMaintenanceGoldenPath` (two matching `dataMaintenance.confirmButton` elements). No layout regression or new failure was observed.
- [x] `make test-quick` passes.
- [x] `make lint` passes with zero violations.

**Manual verification:**
- Not performed on physical hardware; iPhone 17 iOS 26.5 Simulator UI coverage exercises portrait selection and the existing landscape/iPad/Mac logic is covered by the pure helper tests.

## Prevention

- Keep device-class and orientation layout decisions in a pure, testable helper rather than deriving the view directly from width.
- Test representative ranges around geometry boundaries instead of one device width.
- Do not make UI tests pass implicitly when a required layout control is absent.

## Related

- Transit T-1802
- `specs/transit-v1/requirements.md` requirement 13.1 and 13.7
- `docs/agent-notes/dashboard-views.md`
