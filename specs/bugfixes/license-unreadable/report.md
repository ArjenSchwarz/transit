# Bugfix Report: license-unreadable

**Ticket**: T-402
**Date**: 2026-03-10
**Severity**: Low (visual/cosmetic)

## Problem

The Apache License 2.0 full text view (`LicenseTextView`) renders monospaced text directly on top of `BoardBackground` with no glass panel, frosted material, or other readable surface. The text blends into the gradient background and is difficult to read.

## Root Cause

`LicenseTextView` was implemented with `ScrollView > Text` over `BoardBackground`, unlike every other settings sub-screen which uses platform-appropriate containers:
- iOS: `List` (provides row backgrounds automatically)
- macOS: `LiquidGlassSection` (provides a frosted glass panel)

## Resolution

Split `LicenseTextView` into platform-specific layouts matching the existing patterns:
- **iOS**: Wrapped the license text in a `List > Section`, consistent with `AcknowledgmentsView.iOSLayout` and `SettingsView.iOSSettings`.
- **macOS**: Wrapped the license text in a `LiquidGlassSection` inside a `ScrollView` with the standard 760px max-width layout, consistent with `AcknowledgmentsView.macOSLayout` and `SettingsView.macOSSettings`.

### Files Changed

- `Transit/Transit/Views/Settings/AcknowledgmentsView.swift` — rewrote `LicenseTextView.body` with platform-specific layouts

## Verification

- Build passes on both iOS and macOS
- Unit tests pass (`make test-quick`)
