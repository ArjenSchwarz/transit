# Bugfix Report: macOS Toolbar Not Transparent

**Date:** 2026-02-12
**Status:** Fixed

## Description of the Issue

On macOS, the navigation toolbar in the Dashboard view has an opaque background, preventing the BoardBackground gradient mesh from bleeding through to the top of the window. On iOS, the toolbar is translucent and the gradient is visible behind it, which is the expected Liquid Glass behaviour.

**Reproduction steps:**
1. Launch Transit on macOS
2. Observe the toolbar area at the top of the Dashboard
3. The toolbar has an opaque background instead of being transparent

**Impact:** Visual-only issue affecting the macOS experience. The app functions correctly but doesn't match the intended Liquid Glass design where the background gradient should extend behind the toolbar.

## Investigation Summary

- **Symptoms examined:** Opaque toolbar background on macOS vs translucent on iOS
- **Code inspected:** `DashboardView.swift`, `KanbanBoardView.swift`, `BoardBackground.swift`, `TransitApp.swift`, `ColumnView.swift`
- **Hypotheses tested:** The `BoardBackground` already uses `.ignoresSafeArea()` so it extends behind the toolbar area. The issue is that the macOS window toolbar renders with a default opaque background, unlike iOS where `.toolbarTitleDisplayMode(.inline)` automatically gets the Liquid Glass translucent treatment.

## Discovered Root Cause

The macOS window toolbar defaults to an opaque background. Unlike iOS where inline navigation bars automatically become translucent with Liquid Glass, macOS requires an explicit opt-out from the default opaque toolbar background.

**Defect type:** Missing platform-specific modifier

**Why it occurred:** The DashboardView was written with iOS as the primary target. The `.toolbarTitleDisplayMode(.inline)` modifier works well on iOS for Liquid Glass but doesn't control macOS toolbar transparency.

**Contributing factors:** macOS and iOS handle toolbar rendering differently. iOS inline navigation bars are translucent by default; macOS window toolbars are opaque by default.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Views/Dashboard/DashboardView.swift:68-70` - Added `#if os(macOS) .toolbarBackgroundVisibility(.hidden, for: .windowToolbar) #endif` to hide the macOS toolbar background

**Approach rationale:** `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` is the standard SwiftUI API for controlling toolbar background visibility on macOS. Wrapping in `#if os(macOS)` avoids any side effects on iOS where the toolbar already behaves correctly.

**Alternatives considered:**
- `.toolbarBackground(.hidden, for: .windowToolbar)` - Older API variant, `.toolbarBackgroundVisibility` is the preferred modern equivalent
- Applying on both platforms without `#if os(macOS)` - Unnecessary and could affect iOS behaviour which already works

## Regression Test

No automated regression test was created. Toolbar background transparency is a visual property that cannot be meaningfully inspected programmatically. The fix is a single declarative SwiftUI modifier guarded by a platform check.

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Views/Dashboard/DashboardView.swift` | Added `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` for macOS |

## Verification

**Automated:**
- [x] Full test suite passes (`make test-quick`)
- [x] Linters pass (`make lint`)
- [x] macOS build succeeds (`make build-macos`)

**Manual verification:**
- Launch Transit on macOS and verify the toolbar area is transparent with the BoardBackground gradient visible behind it
- Verify column headers (swimlane titles) remain in their correct position
- Verify iOS behaviour is unchanged

## Prevention

**Recommendations to avoid similar bugs:**
- When adding toolbar or navigation styling, test on both macOS and iOS — they handle toolbar rendering differently
- Document platform-specific toolbar behaviour in agent notes

## Related

- Task T-40: Toolbar should be transparent in liquid glass
