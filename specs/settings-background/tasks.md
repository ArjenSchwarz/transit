---
references:
    - specs/settings-background/smolspec.md
---
# Settings Background

- [x] 1. Add theme resolution to SettingsView <!-- id:a1theme -->
  - Add `@Environment(\.colorScheme)` and `resolvedTheme` computed property to SettingsView, following the same pattern as DashboardView.

- [x] 2. Apply BoardBackground on macOS settings <!-- id:b2macos -->
  - On the macOSSettings ScrollView, add `.scrollContentBackground(.hidden)`, `.background { BoardBackground(theme: resolvedTheme) }`, and `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`. LiquidGlassSection content must remain readable against the gradient. Build and verify visually.
  - Blocked-by: a1theme (Add theme resolution to SettingsView)

- [x] 3. Apply BoardBackground on iOS settings <!-- id:c3iosbg -->
  - On the iOSSettings List, add `.scrollContentBackground(.hidden)` and `.background { BoardBackground(theme: resolvedTheme) }`. If grouped list row materials are too opaque, apply `.listRowBackground(Color.clear)` on each Section. Build and verify visually on simulator.
  - Blocked-by: a1theme (Add theme resolution to SettingsView)

- [x] 4. Verify immediate theme update on both platforms <!-- id:d4verfy -->
  - Change the theme picker on Settings and confirm the background updates instantly without navigating away. Test all four theme options (Follow System, Universal, Light, Dark) on both macOS and iOS. Confirm navigating back to dashboard still shows the correct background.
  - Blocked-by: b2macos (Apply BoardBackground on macOS settings), c3iosbg (Apply BoardBackground on iOS settings)

- [x] 5. Lint and build clean on both platforms <!-- id:e5build -->
  - Run `make lint` and `make build`. Fix any warnings or errors introduced by the changes.
  - Blocked-by: d4verfy (Verify immediate theme update on both platforms)
