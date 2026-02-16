# Bugfix Report: TextEditor Background

**Date:** 2026-02-16
**Status:** Fixed

## Description of the Issue

TextEditor fields on macOS did not have a visible background, making them indistinguishable from the surrounding glass section background. Users could not tell these were editable input fields.

**Reproduction steps:**
1. Open Transit on macOS
2. Create or edit a task and look at the Description field
3. Open the Comments section on a task detail view
4. Observe that both TextEditor fields blend into the LiquidGlassSection background with no visual boundary

**Impact:** Moderate UX issue on macOS. Users cannot identify editable text areas, making the description and comment fields effectively invisible until clicked.

## Investigation Summary

Searched all TextEditor usages across the codebase and compared iOS vs macOS rendering paths.

- **Symptoms examined:** TextEditor fields invisible against glass section background on macOS
- **Code inspected:** `TaskEditView.swift`, `AddTaskSheet.swift`, `CommentsSection.swift`, `LiquidGlassSection.swift`, `FormRow.swift`
- **Hypotheses tested:** The macOS TextEditor instances use `.scrollContentBackground(.hidden)` to remove the default NSScrollView background, but no replacement background was provided

## Discovered Root Cause

The macOS form layouts use `.scrollContentBackground(.hidden)` on TextEditor to remove the default system scroll view background. This is a common pattern when placing a TextEditor inside a custom container. However, no replacement background was added, causing the TextEditor to become transparent and blend into the LiquidGlassSection's frosted glass background.

**Defect type:** Missing visual styling

**Why it occurred:** The `.scrollContentBackground(.hidden)` modifier was added to integrate with the custom glass section design, but the complementary background was never applied. On iOS, this is not an issue because the TextEditors in Form sections either don't use `.scrollContentBackground(.hidden)` or get their background from the Form's section styling.

**Contributing factors:** The glass effect background on LiquidGlassSection makes the missing background harder to spot during development since the glass itself provides some visual structure, but not enough to delineate an editable field.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/TaskDetail/TaskEditView.swift` - Added `Color(.textBackgroundColor)` background, 8pt rounded corners, and subtle border to the description TextEditor's ZStack wrapper in the macOS form
- `Transit/Transit/Views/AddTask/AddTaskSheet.swift` - Same treatment for the description TextEditor in the macOS form
- `Transit/Transit/Views/TaskDetail/CommentsSection.swift` - Same treatment for the comment input TextEditor, conditionally applied via `#if os(macOS)`

**Approach rationale:** `Color(.textBackgroundColor)` is the system semantic color for text input backgrounds on macOS (white in light mode, dark grey in dark mode). This respects the user's appearance settings and matches native text field styling. The subtle border (`Color.primary.opacity(0.15)`) provides a clear boundary without being heavy. A 4pt inner padding ensures text doesn't touch the edges of the background.

**Alternatives considered:**
- Using a fixed `Color.white` background - rejected because it would not adapt to dark mode
- Adding `.textFieldStyle(.roundedBorder)` - rejected because TextEditor does not support text field styles
- Removing `.scrollContentBackground(.hidden)` - rejected because the default NSScrollView background would clash with the glass section design

## Regression Test

This is a visual styling bug. SwiftUI does not expose view modifier state for unit testing, and the actual rendering behavior (whether a background is visible) cannot be verified programmatically without snapshot testing infrastructure. The fix is verified through:
- Successful compilation on both macOS and iOS
- Manual visual inspection on macOS

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/TaskDetail/TaskEditView.swift` | Added background, clip shape, and border overlay to macOS description TextEditor |
| `Transit/Transit/Views/AddTask/AddTaskSheet.swift` | Added background, clip shape, and border overlay to macOS description TextEditor |
| `Transit/Transit/Views/TaskDetail/CommentsSection.swift` | Added macOS-conditional background, clip shape, and border overlay to comment input TextEditor |

## Verification

**Automated:**
- [x] Full test suite passes (`make test-quick`)
- [x] Linters pass (`make lint`)
- [x] Builds on both macOS and iOS

**Manual verification:**
- Build and run on macOS, verify TextEditor fields in task edit, add task, and comments sections have visible white backgrounds with subtle borders

## Prevention

**Recommendations to avoid similar bugs:**
- When using `.scrollContentBackground(.hidden)` on TextEditor, always provide a replacement background
- Consider extracting a reusable `StyledTextEditor` component that encapsulates the background/border treatment to ensure consistency

## Related

- Transit ticket: T-72
