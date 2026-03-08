# Implementation Explanation: License Acknowledgments

## Beginner Level

### What Changed / What This Does
Transit now has an "Acknowledgments" screen accessible from Settings that lists all 24 open-source libraries the app depends on. Each library shows its name and a link to its source code repository. Tapping any package navigates to a screen displaying the Apache License 2.0 text that governs how those libraries can be used.

### Why It Matters
Apps distributed on the App Store that use open-source software are legally required to credit the authors and display the relevant license terms. Without this screen, Transit would be non-compliant with the Apache 2.0 license obligations of its 24 dependencies. This feature makes Transit ready for App Store submission from a licensing perspective.

### Key Concepts
- **SPM (Swift Package Manager)**: Apple's tool for managing third-party code libraries that Transit depends on. The 24 packages listed are all pulled in through SPM.
- **Apache License 2.0**: A permissive open-source license that allows free use of software as long as proper attribution is given and the license text is included.
- **Acknowledgments view**: A screen listing all third-party libraries, similar to the "Acknowledgments" section found in most iOS/macOS apps under Settings.
- **NavigationDestination**: The mechanism SwiftUI uses to define what screen to show when the user taps a link or button that triggers navigation.

---

## Intermediate Level

### Changes Overview
Five files were modified or created across three layers:

| Layer | File | Change |
|-------|------|--------|
| Navigation | `NavigationDestination.swift` | Added `.acknowledgments` and `.licenseText` enum cases |
| App root | `TransitApp.swift` | Added `navigationDestination(for:)` handlers to instantiate the new views |
| Settings | `SettingsView.swift` | Added NavigationLink rows in both iOS and macOS settings sections |
| Feature | `AcknowledgmentsView.swift` (new) | Package list view, license text view, data model |
| Docs | `CHANGELOG.md` | Release notes entry |

### Implementation Approach
The feature follows Transit's established navigation pattern exactly: define enum cases in `NavigationDestination`, wire them in `TransitApp.swift`, and trigger navigation from the relevant view. No new patterns were introduced.

`AcknowledgmentsView.swift` contains everything for the feature in a single file:
- An `AcknowledgedPackage` struct holding name and repository URL, with `Identifiable` conformance derived from the name.
- A static array of 24 packages, hardcoded and verified against `Package.resolved`.
- Platform-specific layouts: iOS uses a standard `List` with `Section` headers; macOS uses `ScrollView` with `LiquidGlassSection` and `FormRow`, matching how the rest of macOS Settings is built.
- A shared `packageRow` function that renders consistently across platforms.
- `LicenseTextView` displays the full Apache 2.0 text in a monospaced font, navigated to from each package row or a shared link since all packages use the same license.

Theme integration uses the existing `@Environment(\.resolvedTheme)` key, so the views automatically adapt to the user's chosen theme (System, Universal, Light, Dark) with the correct `BoardBackground`.

### Trade-offs
**Hardcoded list vs. build-time generation**: The package list is a static array rather than being auto-generated from `Package.resolved` at build time. This is simpler and avoids build script complexity, but means the list must be manually updated when dependencies change.

**Single license text vs. per-package licenses**: Since all 24 packages happen to use Apache 2.0, a single `LicenseTextView` is shared. This is a simplification that would need rethinking if a non-Apache dependency were ever added.

**Single file vs. multiple files**: All types live in one ~345-line file. This keeps the feature self-contained and easy to find, at the cost of a somewhat long file. Given the feature's simplicity and low change frequency, this is a reasonable choice.

---

## Expert Level

### Technical Deep Dive
The `AcknowledgedPackage` struct uses a computed `id` derived from `name`, making it `Identifiable` without requiring a stored UUID. This is safe here because package names are unique within a dependency graph and the list is static.

The navigation flow is two-level: Settings pushes `.acknowledgments`, and from the acknowledgments list, tapping the license indicator pushes `.licenseText`. Both are value-type enum cases handled by `navigationDestination(for:)` on the root `NavigationStack`, consistent with Transit's flat navigation architecture (single stack, no nested stacks or sheets for this flow).

Platform branching uses `#if os(macOS)` and `#if os(iOS)` compile-time directives rather than runtime checks. The macOS path uses `LiquidGlassSection` and `FormRow` (Transit's custom macOS settings components), while iOS uses standard `List` and `Section`. The `packageRow` function is shared across both platforms, keeping the per-package rendering consistent.

The repository URL is rendered as a tappable `Link` that opens in the system browser. This is a SwiftUI `Link` view, not a `NavigationLink`, so it correctly exits the app rather than trying to navigate internally.

The license text is stored as a string literal within `LicenseTextView`. It uses a monospaced font for faithful reproduction of the license formatting. The view respects the resolved theme for background rendering via `BoardBackground`.

### Architecture Impact
Minimal. The feature adds two enum cases to `NavigationDestination` and two corresponding handlers in `TransitApp.swift`. No new services, no new SwiftData entities, no new environment keys. The feature is entirely additive and self-contained.

The only coupling point is the `NavigationDestination` enum, which is Transit's central navigation registry. Adding cases here is the expected pattern and does not affect existing navigation paths.

### Potential Issues
1. **Stale package list**: The hardcoded list can drift from `Package.resolved` if dependencies are added, removed, or renamed. There is no compile-time or CI check to catch this. A developer must remember to update the list manually.

2. **Single-license assumption**: The entire architecture assumes Apache 2.0 for all packages. If a dependency with a different license (MIT, BSD, etc.) is added, `LicenseTextView` would need to accept a license parameter or the navigation model would need to change to pass license type.

3. **Deep link fragility**: If a future feature adds deep linking or state restoration, the `.licenseText` destination has no associated data (it is a plain enum case). This works because there is only one license, but would need to carry a license identifier if multiple licenses were supported.

4. **No offline fallback for repository links**: The `Link` views point to GitHub URLs. If the user taps one without connectivity, they get the system's default offline error. This is standard iOS/macOS behavior and not a bug, but worth noting.

---

## Completeness Assessment

### Fully Implemented
- Acknowledgments screen accessible from Settings on both iOS and macOS
- All 24 SPM dependencies listed with names and repository URLs
- Full Apache License 2.0 text display
- Platform-appropriate layouts (iOS List vs. macOS LiquidGlassSection)
- Theme-aware backgrounds via existing theme system
- Navigation wired through the standard `NavigationDestination` pattern
- CHANGELOG updated

### Partially Implemented
- Nothing is partially implemented; the spec's required scope is fully covered.

### Missing
The following were explicitly scoped out per the smolspec:
- **Build-time generation from `Package.resolved`**: Would eliminate manual list maintenance
- **Grouping by package owner**: Could improve readability for packages from the same organization
- **Localization of license text**: License text is English-only, which is standard practice since licenses are legal documents typically kept in their original language
- **CI check comparing hardcoded list to `Package.resolved`**: Would catch drift automatically
- **Package versions**: Not displayed; would require reading `Package.resolved` at build time or runtime
