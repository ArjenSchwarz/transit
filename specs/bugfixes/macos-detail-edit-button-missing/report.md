# Bugfix Report: macOS Detail View Edit Button Missing

**Date:** 2026-02-13
**Status:** Fixed

## Description of the Issue

On macOS, the task detail view (sheet) only shows the back and share buttons in the toolbar. The edit button is missing. On iOS, all three buttons are visible.

**Reproduction steps:**
1. Launch Transit on macOS
2. Tap a task card on the kanban board to open the detail sheet
3. Observe the toolbar — only the back (chevron) and share buttons are present; the edit button is missing

**Impact:** Users on macOS cannot edit tasks from the detail view. Functional regression introduced in commit `4efbdac` (T-41: Add share button).

## Investigation Summary

- **Symptoms examined:** Edit button missing on macOS but present on iOS
- **Code inspected:** `TaskDetailView.swift` toolbar configuration, commit `4efbdac` diff
- **Hypotheses tested:** The ShareLink addition in T-41 created two separate `ToolbarItem` blocks with `.primaryAction` placement. On macOS, the sheet's `NavigationStack` toolbar renders these differently than iOS — the second item (Edit) is not displayed.

## Discovered Root Cause

When the ShareLink was added in commit `4efbdac`, it was added as a separate `ToolbarItem(placement: .primaryAction)` before the existing Edit button (also `.primaryAction`). On macOS, a sheet's `NavigationStack` toolbar only renders one trailing-side placement — multiple `ToolbarItem` blocks with `.primaryAction`, or items split across `.primaryAction` and `.confirmationAction`, result in only one being visible.

**Defect type:** Platform-specific toolbar rendering issue

**Why it occurred:** macOS sheet toolbars only support a single trailing toolbar slot. Multiple trailing placements (`.primaryAction`, `.confirmationAction`) compete, and only one renders. On iOS, all trailing placements render correctly side by side.

**Contributing factors:** macOS and iOS handle trailing toolbar placements differently in sheets. On macOS, both separate `ToolbarItem` blocks with the same placement AND items in different trailing placements fail to coexist.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/TaskDetail/TaskDetailView.swift:28-36` — Replaced two separate `ToolbarItem(placement: .primaryAction)` blocks with a single `ToolbarItem(placement: .confirmationAction)` containing an `HStack` with both the ShareLink and Edit button (pencil icon only). This ensures both buttons render within a single toolbar slot.

**Approach rationale:** Since macOS sheet toolbars only render one trailing toolbar slot, both buttons must live in a single `ToolbarItem`. An `HStack` inside one `ToolbarItem` avoids the slot competition entirely. The edit button uses an icon-only style (pencil) for consistent rendering alongside the share icon.

**Alternatives considered:**
- `ToolbarItemGroup(placement: .primaryAction)` with both items — still only rendered the ShareLink on macOS
- Separate placements (`.primaryAction` + `.confirmationAction`) — macOS only rendered the `.confirmationAction` item, hiding the ShareLink
- Adding a `ToolbarSpacer` between items — creates separate glass bubbles but doesn't solve the single-slot limitation

## Regression Test

No automated regression test was created. Toolbar item visibility in a sheet is a platform-specific rendering behaviour that cannot be inspected programmatically in unit tests.

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/TaskDetail/TaskDetailView.swift` | Replaced two `ToolbarItem(.primaryAction)` with one `ToolbarItem(.confirmationAction)` containing an HStack |

## Verification

**Automated:**
- [x] Full test suite passes (`make test-quick`)
- [x] Linters pass (`make lint`)
- [x] macOS build succeeds (`make build-macos`)

**Manual verification:**
- Launch Transit on macOS and open a task detail sheet — both share and edit buttons should be visible in the toolbar
- Verify the edit button opens the edit sheet
- Verify iOS behaviour is unchanged (both buttons still visible)

## Prevention

**Recommendations to avoid similar bugs:**
- On macOS, sheet NavigationStack toolbars only support a single trailing toolbar slot — put multiple trailing buttons in one `ToolbarItem` with an HStack
- Test toolbar changes on both macOS and iOS — they render toolbar items differently in sheets

## Related

- Task T-48: macOS detail view edit button missing
- Commit `4efbdac` (T-41): Add share button — introduced the regression
