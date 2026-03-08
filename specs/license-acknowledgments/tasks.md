---
references:
    - specs/license-acknowledgments/smolspec.md
---
# License Acknowledgments

## Navigation Wiring

- [ ] 1. Add .acknowledgments case to NavigationDestination enum and wire destination handler in TransitApp.swift <!-- id:n86ouf9 -->

- [ ] 2. Add Acknowledgments navigation row to SettingsView on both iOS (iOSGeneralSection) and macOS (macOSGeneralSection) <!-- id:n86oufa -->
  - Blocked-by: n86ouf9 (Add .acknowledgments case to NavigationDestination enum and wire destination handler in TransitApp.swift)

## Acknowledgments View

- [ ] 3. Define static package data array with all 24 dependencies (name, repository URL) verified against Package.resolved and each packages LICENSE file <!-- id:n86oufb -->
  - Blocked-by: n86ouf9 (Add .acknowledgments case to NavigationDestination enum and wire destination handler in TransitApp.swift)

- [ ] 4. Build AcknowledgmentsView with alphabetical package list, tappable repository URLs, and license text navigation — platform-specific layout (iOS List, macOS ScrollView with LiquidGlassSection) <!-- id:n86oufc -->
  - Blocked-by: n86oufb (Define static package data array with all 24 dependencies (name, repository URL) verified against Package.resolved and each packages LICENSE file)

- [ ] 5. Build license text view displaying full Apache License 2.0 text, pushed via NavigationLink from AcknowledgmentsView <!-- id:n86oufd -->
  - Blocked-by: n86oufc (Build AcknowledgmentsView with alphabetical package list, tappable repository URLs, and license text navigation — platform-specific layout (iOS List, macOS ScrollView with LiquidGlassSection))

## Verification

- [ ] 6. Verify end-to-end navigation from Settings → Acknowledgments → License text on both iOS and macOS; confirm all 24 packages listed and URLs open correctly <!-- id:n86oufe -->
  - Blocked-by: n86oufa (Add Acknowledgments navigation row to SettingsView on both iOS (iOSGeneralSection) and macOS (macOSGeneralSection)), n86oufd (Build license text view displaying full Apache License 2.0 text, pushed via NavigationLink from AcknowledgmentsView)

- [ ] 7. Run linter and build for both platforms to confirm no warnings or errors <!-- id:n86ouff -->
  - Blocked-by: n86oufe (Verify end-to-end navigation from Settings → Acknowledgments → License text on both iOS and macOS; confirm all 24 packages listed and URLs open correctly)
