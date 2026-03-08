# License Acknowledgments

## Overview

Add an "Acknowledgments" section to the Settings view that lists all open-source dependencies used by Transit, with their Apache 2.0 license text. This is required for App Store distribution compliance. All 24 SPM packages use the Apache License 2.0, so a single shared license text with per-package attribution keeps the UI clean.

## Requirements

- The system MUST display an "Acknowledgments" navigation row in Settings on both iOS and macOS
- The system MUST navigate to a dedicated view listing all 24 open-source dependencies alphabetically
- The system MUST show each dependency's name and repository URL
- The system MUST display the full Apache License 2.0 text on a separate view, navigable via a "License" link
- The system MUST verify each package's license during implementation (all are expected to be Apache 2.0)
- The system SHOULD make repository URLs tappable to open in the default browser
- The system MAY show package versions (hardcoded, updated manually when dependencies change)

## Implementation Approach

**Navigation wiring (3 files):**

- Add `.acknowledgments` case to `NavigationDestination` enum (`Transit/Transit/Models/NavigationDestination.swift`)
- Add destination handler in `TransitApp.swift` (`Transit/Transit/TransitApp.swift`, line ~105-115)
- Add "Acknowledgments" row in `SettingsView.swift` (`Transit/Transit/Views/Settings/SettingsView.swift`):
  - iOS: `NavigationLink` row in `iOSGeneralSection` (after the iCloud Sync toggle)
  - macOS: `NavigationLink` row in `macOSGeneralSection` grid (after the iCloud Sync row)

**New views (1-2 files):**

- Create `Transit/Transit/Views/Settings/AcknowledgmentsView.swift`:
  - Static array of package structs (name, repositoryURL string)
  - Flat alphabetical list of all 24 packages
  - Each row shows package name and tappable `Link` to repository URL
  - "Apache License 2.0" row at the top or bottom that navigates to a license text view
  - Platform-specific layout: iOS uses `List`; macOS uses `ScrollView` > `VStack` with `LiquidGlassSection` (matching `SettingsView.swift` patterns)
  - License text displayed on a separate pushed view (via `NavigationLink`) rather than inline `DisclosureGroup`, since the Apache 2.0 text is ~170 lines

**Data source:**

- Hardcode the package list as a static array — no build-time code generation (the project has no existing code gen patterns and dependencies change rarely)
- Package data sourced from `Package.resolved` at `Transit/Transit.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

**Existing patterns to follow:**

- Navigation: `NavigationDestination` enum + `navigationDestination(for:)` in `TransitApp.swift` (lines 105-116)
- Settings rows: iOS `Section` with `NavigationLink(value:)` / macOS `LiquidGlassSection` with `FormRow` and `Grid`
- Platform branching: `#if os(macOS)` / `#if os(iOS)` conditional compilation

**Out of scope:**

- Build-time generation from Package.resolved
- Grouping by package owner (flat alphabetical is sufficient for a compliance view)
- Localization of license text
- CI check comparing hardcoded list to Package.resolved (potential follow-up)

## Risks and Assumptions

- **Assumption**: All 24 current dependencies use Apache License 2.0 — MUST be verified during implementation by checking each package's LICENSE file on GitHub
- **Risk**: Package list becomes stale when dependencies are added or updated | **Mitigation**: Add a code comment in the data array referencing Package.resolved and noting it should be updated when dependencies change. A unit test comparing the count against Package.resolved could catch drift (follow-up)
- **Assumption**: A single shared Apache 2.0 license text satisfies compliance — the Apache 2.0 license requires reproduction of the license notice, not per-package customisation beyond attribution
