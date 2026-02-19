# Settings Background

## Overview

The Settings view currently uses default system backgrounds (macOS window background, iOS grouped list background) while the rest of the app uses `BoardBackground` — a themed radial gradient mesh. This makes Settings feel disconnected from the main dashboard. The background should match the dashboard and update immediately when the user changes theme in the Appearance section.

## Requirements

- The Settings view MUST display `BoardBackground` behind its content, matching the dashboard appearance.
- The background MUST update immediately when the user changes the theme picker — no navigation required.
- The existing frosted glass sections (macOS `LiquidGlassSection`) and iOS list rows MUST remain readable against the new background.
- The toolbar area MUST be transparent on macOS so the background shows through, matching the dashboard behaviour.

## Implementation Approach

All changes are in `Transit/Transit/Views/Settings/SettingsView.swift`. The pattern is copied directly from `DashboardView` (lines 13, 17, 22–24, 60–62, 71).

**Steps:**

1. Add `@Environment(\.colorScheme) private var colorScheme` to SettingsView properties.
2. Add computed property `resolvedTheme` using the existing `appTheme` storage:
   ```swift
   private var resolvedTheme: ResolvedTheme {
       (AppTheme(rawValue: appTheme) ?? .followSystem).resolved(with: colorScheme)
   }
   ```
3. **macOS:** On the `macOSSettings` ScrollView, add:
   - `.scrollContentBackground(.hidden)` to remove the default window background
   - `.background { BoardBackground(theme: resolvedTheme) }` to render the gradient mesh
   - `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` to make the toolbar transparent
4. **iOS:** On the `iOSSettings` List, add:
   - `.scrollContentBackground(.hidden)` to remove the default grouped list background
   - `.background { BoardBackground(theme: resolvedTheme) }` to render the gradient mesh
   - If grouped list row backgrounds are too opaque and obscure the gradient, apply `.listRowBackground(Color.clear)` on each Section to make rows transparent. This is the same trade-off macOS makes with `LiquidGlassSection` — content sits directly on the gradient.

**Dependencies:** `BoardBackground` (already exists), `ResolvedTheme`/`AppTheme` (already imported).

**Out of Scope:** No changes to BoardBackground itself, no changes to theme logic, no changes to other views.

## Risks and Assumptions

- **Risk:** iOS List row backgrounds may not be transparent enough against the gradient, reducing readability. **Mitigation:** Apply `.listRowBackground(Color.clear)` on each Section if the default materials are too opaque. Verify visually — iOS 26 Liquid Glass materials may already be sufficiently transparent.
- **Assumption:** `@AppStorage("appTheme")` triggers a SwiftUI view update when changed from the picker within the same view. This is the standard behaviour and is already relied upon by DashboardView.
