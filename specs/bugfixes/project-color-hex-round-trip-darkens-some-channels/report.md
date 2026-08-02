# Bugfix Report: Project Color Hex Round-Trip Darkens Some Channels

**Date:** 2026-08-02
**Status:** In Progress

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

_To be completed after the implementation is verified._

## Regression Test

**Test file:** `Transit/TransitTests/ColorHexRoundTripTests.swift`
**Test name:** `everyRedByteRoundTripsWithoutDarkening`, `everyGreenByteRoundTripsWithoutDarkening`, `everyBlueByteRoundTripsWithoutDarkening`, `componentsJustBelowEveryByteBoundaryRoundToNearestByte`

**What it verifies:** Every RGB byte value `0...255` survives `Color(hex:)`/`hexString` round-tripping, and deterministic sRGB `Color.Resolved` components immediately below every byte boundary round to the intended byte. The format test verifies uppercase six-digit RGB without `#` and confirms opacity remains excluded.

**Run command:** `make test-quick`

## Affected Files

| File | Change |
|------|--------|
| `Transit/TransitTests/ColorHexRoundTripTests.swift` | Regression coverage for RGB byte round trips, boundary rounding, alpha, and format. |
| `Transit/Extensions/Color+Codable.swift` | Pending nearest-byte conversion fix. |
| `CHANGELOG.md` | Pending user-visible bugfix entry. |

## Verification

**Automated:**
- [ ] Regression test passes
- [ ] Full test suite passes
- [ ] Linters/validators pass

**Manual verification:**
- Deterministic pre-fix run fails the new tests against the truncating implementation.

## Prevention

**Recommendations to avoid similar bugs:**
- Quantize resolved floating-point color components by rounding to the nearest byte after clamping.
- Keep explicit tests for every byte boundary and the persisted six-digit RGB format.

## Related

- Transit T-1807
