# Bugfix Report: Theme Selector Not Applied

**Date:** 2026-02-15
**Status:** Fixed
**Transit Ticket:** T-62

## Description of the Issue

Theme selection in Settings only changed custom styling (background gradients, glass materials, card borders) but did not override the system color scheme. Standard SwiftUI elements (text colors, system controls, backgrounds) remained in the system's appearance regardless of theme selection.

**Reproduction steps:**
1. Set system appearance to Dark mode
2. Open Transit Settings and select "Light" theme
3. Observe that background gradients change but text, controls, and system materials remain dark — making the UI unreadable

**Impact:** High severity for users who select a theme that opposes their system setting. The "Universal" theme also looked inconsistent across light/dark system modes.

## Investigation Summary

The theme system was inspected end-to-end: storage, resolution, and application.

- **Symptoms examined:** Custom gradients and materials changed correctly per theme, but system UI elements did not follow
- **Code inspected:** `AppTheme.swift` (model), `TransitApp.swift` (app root), `DashboardView.swift`, `BoardBackground.swift`, `ColumnView.swift`, `TaskCardView.swift`
- **Hypotheses tested:** Whether `.preferredColorScheme()` was applied anywhere in the view hierarchy — it was not

## Discovered Root Cause

The app resolved `AppTheme` to a `ResolvedTheme` and used it to switch custom styling (gradients, materials, borders), but never called `.preferredColorScheme()` to tell SwiftUI to override the system color scheme.

**Defect type:** Missing modifier — incomplete theme implementation

**Why it occurred:** The theme system was built as a custom styling layer (gradients, materials) without connecting it to SwiftUI's color scheme override mechanism.

**Contributing factors:** The custom styling adapted correctly per theme, masking the fact that system elements were not following suit during initial development.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Models/AppTheme.swift:18-24` - Added `preferredColorScheme` computed property mapping each theme to its `ColorScheme?` value
- `Transit/Transit/TransitApp.swift:80-82` - Added `@AppStorage("appTheme")` and applied `.preferredColorScheme()` to the root `NavigationStack`

**Approach rationale:** Applying `.preferredColorScheme()` at the app root ensures all SwiftUI elements — text, controls, materials, system backgrounds — follow the selected theme. This is the standard SwiftUI mechanism for overriding appearance.

**Design decision for Universal:** Maps to `.light` because the universal theme's white overlays and mid-saturation vibrant colors were designed for lighter backgrounds. Forcing a specific scheme is the only way to achieve a consistent appearance, since SwiftUI materials (`ultraThinMaterial`) are inherently adaptive.

**Alternatives considered:**
- Per-view `.preferredColorScheme()` — Rejected because it would need to be applied to every view individually and is easy to miss
- Making Universal follow system — Rejected because the user explicitly wants Universal to look the same regardless of system appearance

## Regression Test

**Test file:** `Transit/TransitTests/AppThemeTests.swift`
**Test names:** `followSystemReturnsNil`, `lightReturnsLight`, `darkReturnsDark`, `universalReturnsLight`, plus resolved theme tests

**What it verifies:** Each `AppTheme` case returns the correct `preferredColorScheme` value, and the `resolved(with:)` method behaves correctly for all combinations of theme and system color scheme.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Models/AppTheme.swift` | Added `preferredColorScheme` computed property |
| `Transit/Transit/TransitApp.swift` | Added `@AppStorage` + `.preferredColorScheme()` modifier |
| `Transit/TransitTests/AppThemeTests.swift` | New regression test file |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes
- [x] Linters pass

**Manual verification:**
- Build succeeds for macOS target

## Prevention

- When adding theme/appearance controls, always connect them to `.preferredColorScheme()` at the app root — custom styling alone is insufficient
- Test theme changes with opposing system appearances during development

## Related

- Transit ticket: T-62
