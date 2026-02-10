# Bugfix Report: Drag-and-Drop Fails for Most Columns on iPhone

**Date:** 2026-02-10
**Status:** Fixed

## Description of the Issue

On iPhone, drag-and-drop to change task status only worked for the Planning and Done columns. Attempts to drop tasks on Idea, Spec, or In Progress columns were ignored.

**Reproduction steps:**
1. Open Transit on iPhone (portrait or landscape)
2. Long-press a task card to initiate a drag
3. Attempt to drop it on a column other than Planning or Done
4. Observe the drop is rejected or has no effect

**Impact:** Drag-and-drop, the primary status-change mechanism on the dashboard, was non-functional for 3 of 5 columns on iPhone. Users could only change status via the task detail view.

## Investigation Summary

- **Symptoms examined:** Drops accepted by Planning and Done columns but rejected by Idea, Spec, In Progress
- **Code inspected:** ColumnView, KanbanBoardView, SingleColumnView, DashboardView, TaskCardView, StatusEngine, TaskService, TaskStatus
- **Hypotheses tested:**
  - Status transition validation rejecting certain moves — ruled out (StatusEngine accepts all transitions)
  - TaskService.updateStatus throwing for certain columns — ruled out (no validation on status values)
  - Gesture conflict between `.onTapGesture` and `.draggable()` — ruled out (same on all columns)
  - Query not finding task during drop — ruled out (lookup by UUID, query has no filter)

## Discovered Root Cause

Three compounding defects:

**Defect 1 — ColumnView missing `.contentShape(.rect)`**

The VStack containing column content had `.dropDestination` but no explicit content shape. SwiftUI's drop hit-testing may not cover the full frame when the VStack contains Spacers (empty columns) or a nested ScrollView (columns with tasks). The codebase's own FilterPopoverView already used `.contentShape(Rectangle())` to work around the same class of issue.

**Defect 2 — KanbanBoardView using `.scrollTargetBehavior(.paging)`**

The horizontal ScrollView used `.paging`, which scrolls by full viewport width (2-3 columns at once). During a drag operation, auto-scroll jumps aggressively between pages instead of scrolling column-by-column. This made it difficult or impossible to reach intermediate columns (Spec, In Progress) while dragging.

**Defect 3 — SingleColumnView had no cross-column drop mechanism**

On iPhone portrait, only one column is visible at a time via a segmented control. The single visible ColumnView's `.dropDestination` mapped to the currently selected column. There was no way to drop a task onto a *different* column because the segmented control didn't accept drops.

**Defect type:** Missing hit-testing configuration, scroll behavior conflict, missing interaction path

**Why it occurred:** The drag-and-drop implementation was tested at the data/logic level (StatusEngine transitions) but the UI-level interaction — particularly how `.dropDestination` behaves inside nested ScrollViews and with paging — wasn't validated on iPhone form factors.

**Contributing factors:** iPhone portrait shows only 1 column; iPhone landscape shows 2-3. The multi-column KanbanBoardView was designed for iPad/Mac where all 5 columns are visible simultaneously.

## Resolution for the Issue

**Changes made:**
- `ColumnView.swift:9` — Added `@State private var isDropTargeted` for tracking hover state
- `ColumnView.swift:50` — Added `.contentShape(.rect)` to ensure the full column area is a valid drop target
- `ColumnView.swift:51-56` — Added tint background when a drag hovers over the column (visual feedback)
- `ColumnView.swift:60-63` — Added `isTargeted:` parameter to `.dropDestination` with animation
- `KanbanBoardView.swift:30` — Added `.scrollTargetLayout()` on the HStack for per-column scroll alignment
- `KanbanBoardView.swift:32` — Changed `.scrollTargetBehavior(.paging)` to `.viewAligned` for column-by-column scrolling
- `SingleColumnView.swift:14-42` — Wrapped Picker in ZStack with invisible drop target overlay; each segment maps to a column and accepts drops. When a drag hovers over a segment, the selected tab switches to preview the target column.

**Approach rationale:** Each fix is minimal and targeted. `.contentShape(.rect)` is the standard SwiftUI pattern for ensuring full-frame hit testing. `.viewAligned` gives smoother per-column scroll stops that work naturally with drag-and-drop auto-scroll. The ZStack overlay on SingleColumnView keeps the native segmented control appearance while adding drop support.

**Alternatives considered:**
- Replacing the native Picker with a custom segmented control — would lose Liquid Glass styling
- Adding a separate "drop zone" bar below the segmented control — visual clutter, redundant labels
- Making the ColumnView drop destination catch-all and showing a column picker menu on drop — poor discoverability

## Regression Test

**Test file:** `Transit/TransitTests/DragDropStatusTests.swift`
**Test name:** `dropAcceptedForAllColumns(targetColumn:)`

**What it verifies:** A parameterized test that drops a task (starting from `.inProgress`) onto every `DashboardColumn` and asserts the resulting status matches `column.primaryStatus`. Covers all 5 columns in a single test definition.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Dashboard/ColumnView.swift` | Added `.contentShape(.rect)`, drop target visual feedback, `isTargeted` state |
| `Transit/Transit/Views/Dashboard/KanbanBoardView.swift` | Changed `.paging` to `.viewAligned` + `.scrollTargetLayout()` |
| `Transit/Transit/Views/Dashboard/SingleColumnView.swift` | Added ZStack overlay with per-segment drop targets on the segmented control |
| `Transit/TransitTests/DragDropStatusTests.swift` | Added parameterized regression test for all column drops |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (`make test-quick`)
- [x] Linters pass (`make lint`)
- [x] iOS build succeeds (`make build-ios`)
- [x] macOS build succeeds (`make build-macos`)

**Manual verification:**
- Needs manual testing on iPhone in both portrait and landscape orientations
- Verify segmented control taps still work correctly in SingleColumnView
- Verify drag hover highlights appear on columns
- Verify `.viewAligned` scroll snapping feels natural

## Prevention

**Recommendations to avoid similar bugs:**
- Always add `.contentShape(.rect)` to views that use `.dropDestination`, especially when containing Spacers or ScrollViews
- Test drag-and-drop interactions on iPhone-sized layouts, not just iPad/Mac
- Avoid `.scrollTargetBehavior(.paging)` when the scroll content also needs to support drag-and-drop — prefer `.viewAligned` for finer scroll control
- Consider adding UI tests for drag-and-drop in SingleColumnView layout

## Related

- `docs/agent-notes/dashboard-views.md` — Dashboard architecture notes
- `docs/transit-design-doc.md` — Design spec for dashboard and drag-and-drop requirements
