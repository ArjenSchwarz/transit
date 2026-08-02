# Bugfix Report: Project Color Hex Round-Trip Darkens Some Channels

**Date:** 2026-08-02
**Status:** Fixed

## Description of the Issue

Project colors can darken when an existing project is opened and saved without changing the color. `Color.hexString` converts resolved RGB components to byte values with `Int(component * 255)`. When a resolved component is just below an exact byte boundary, truncation lowers that channel by one byte.

**Reproduction steps:**
1. Store a project color such as `#10xxxx`.
2. Open the project editor and save without changing the color.
3. Observe that the serialized color can contain `0F` for the original `10` channel.

**Impact:** Project colors can drift darker after ordinary edit/save cycles. Repeated edits can compound the drift across affected channels.

## Investigation Summary

The investigation followed the systematic debugging workflow: establish the expected and actual serialization behavior, inspect the conversion implementation and callers, classify boundary and data-flow defects, and verify the defect with deterministic resolved-color tests.

- **Symptoms examined:** Values such as `0x10` becoming `0x0F` and `0x3F` becoming `0x3E`; alpha and stored-format behavior were also checked.
- **Code inspected:** `Transit/Extensions/Color+Codable.swift`, `Views/Settings/ProjectEditView.swift`, `Services/ProjectEditMerge.swift`, project model/service color fields, and all `hexString`/`Color(hex:)` call sites.
- **Hypotheses tested:** The project editor's merge/save path was not independently rewriting the color; the loss occurs in resolved-component-to-byte conversion. The serializer intentionally stores RGB only, so opacity is not part of this bug.

## Discovered Root Cause

`Color.hexString` clamps each resolved component and immediately converts `component * 255` to `Int`. Integer conversion truncates toward zero. SwiftUI's resolved components can be representationally just below an exact byte boundary, so a mathematically exact byte is serialized as the preceding byte.

**Defect type:** Numeric conversion / boundary condition.

**Why it occurred:** The implementation treated floating-point resolved components as exact byte fractions and used truncation rather than nearest-byte quantization.

**Contributing factors:** SwiftUI color resolution is platform-aware and may use floating-point values that differ slightly from the original picker input. Project storage uses a six-digit uppercase RGB string without a leading `#`; opacity is intentionally omitted.

## Resolution for the Issue

**Changes made:**
- `Transit/Transit/Extensions/Color+Codable.swift:21-37` - Replaced truncating `Int(component * 255)` conversions with a shared `roundedByte` helper that rejects non-finite values, clamps components to `0...1`, rounds to the nearest byte, and then converts to `Int`.
- `Transit/TransitTests/ColorHexRoundTripTests.swift:8-92` - Added all-byte RGB round-trip tests, deterministic just-below-boundary tests using explicit sRGB `Color.Resolved` values at Float precision, explicit lower/upper clamping coverage, and format/opacity assertions.
- `CHANGELOG.md` - Documented the fixed behavior and regression coverage.

**Approach rationale:** Rounding after clamping directly addresses the numeric root cause while leaving `Color.resolve(in: EnvironmentValues())` in place. That preserves the existing platform-aware SwiftUI resolution path and avoids the UIColor/NSColor actor-isolation issues documented for this project. The six-digit uppercase RGB format and intentional omission of opacity remain unchanged.

**Alternatives considered:**
- Converting through `UIColor`/`NSColor` - Not chosen because it introduces platform-specific code and actor-isolation concerns without fixing the quantization rule.
- Changing the stored format to include alpha - Not chosen because project color storage is intentionally RGB-only and the bug is channel quantization, not opacity handling.

## Regression Test

**Test file:** `Transit/TransitTests/ColorHexRoundTripTests.swift`
**Test name:** `everyRedByteRoundTripsWithoutDarkening`, `everyGreenByteRoundTripsWithoutDarkening`, `everyBlueByteRoundTripsWithoutDarkening`, `componentsJustBelowEveryByteBoundaryRoundToNearestByte`, `resolvedComponentsAreClampedBeforeRounding`

**What it verifies:** Every RGB byte value `0...255` survives `Color(hex:)`/`hexString` round-tripping, deterministic sRGB `Color.Resolved` components immediately below every byte boundary round to the intended byte, and out-of-range components clamp to the valid byte range. The format test verifies uppercase six-digit RGB without `#` and confirms opacity remains excluded.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/Transit/Extensions/Color+Codable.swift` | Nearest-byte quantization for resolved RGB components. |
| `Transit/TransitTests/ColorHexRoundTripTests.swift` | Regression coverage for RGB byte round trips, boundary rounding, alpha, and format. |
| `specs/bugfixes/project-color-hex-round-trip-darkens-some-channels/report.md` | Investigation and resolution report. |
| `CHANGELOG.md` | User-visible bugfix entry. |

## Verification

**Automated:**
- [x] Focused regression tests pass on macOS (`ColorHexRoundTripTests`, 6 tests)
- [x] Focused regression tests pass on iOS Simulator (`ColorHexRoundTripTests`, 6 tests)
- [x] macOS unit suite passes via `make test-quick`
- [x] Linters/validators pass via `make lint` (0 violations)
- [ ] Full iOS `make test` is not clean: unrelated UI tests `TransitUITests.testClearAll`, `TransitUITests.testEditViewPreservesTaskMilestone`, `TransitUITests.testSettingsHasBackChevron`, `TransitUITests.testSettingsWithNoProjectsShowsCreatePrompt`, `TransitUITests.testTappingGearPushesSettingsView`, and `DataMaintenanceUITests.testDataMaintenanceGoldenPath` failed after the app and unit tests built successfully.

**Manual verification:**
- The pre-fix targeted run failed the color regressions against the truncating implementation.
- The post-fix targeted runs passed all six tests on both macOS and iOS, including every RGB byte value, all three channels immediately below each Float byte boundary, and lower/upper clamping.
- The tests construct explicit sRGB `Color.Resolved` values at the framework's `Float` component precision, so the boundary assertions do not depend on one platform's incidental floating-point representation.

## Prevention

**Recommendations to avoid similar bugs:**
- Quantize resolved floating-point color components by rounding to the nearest byte after clamping.
- Keep explicit tests for every byte boundary and the persisted six-digit RGB format.

## Related

- Transit T-1807
