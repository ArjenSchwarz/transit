# Plan: Frosted Panels Theme with Light/Dark/Universal Modes

## Context

The current dashboard cards use `.regularMaterial` + `.glassEffect(.regular)` which renders as flat grey. Columns have no background styling, and the dashboard has no custom background. The user chose the "Frosted Panels" concept (concept 3) — layered glass with a colourful gradient background — and wants all three variants (Universal, Light, Dark) plus a "Follow System" option, selectable from Settings.

## Approach

### 1. Create `AppTheme` enum

**New file:** `Transit/Transit/Models/AppTheme.swift`

```swift
enum AppTheme: String, CaseIterable {
    case followSystem
    case universal
    case light
    case dark
}

enum ResolvedTheme {
    case universal, light, dark
}
```

- `AppTheme` is the user preference (stored via `@AppStorage("appTheme")`)
- `ResolvedTheme` is what views actually use — `followSystem` collapses to `light` or `dark` based on `colorScheme`
- Add a resolution method: `func resolved(with colorScheme: ColorScheme) -> ResolvedTheme`

### 2. Create `BoardBackground` view

**New file:** `Transit/Transit/Views/Dashboard/BoardBackground.swift`

A view that renders the radial gradient mesh behind the kanban board, adapted per resolved theme:
- **Universal**: Vibrant mid-saturation gradient (indigo, rose, teal, violet blobs)
- **Light**: Pastel version of the same gradient
- **Dark**: Deeper/more saturated version

Uses `Canvas` or layered `RadialGradient` fills. Applied as a `.background` on the board container.

### 3. Update `ColumnView.swift`

Add frosted glass panel styling to each column:
- **Universal**: `rgba(255,255,255,0.07)` equivalent — `.ultraThinMaterial` with low opacity overlay, rounded corners (14pt), subtle border
- **Light**: Brighter frosted panel — `.thinMaterial` or white overlay at ~55% opacity
- **Dark**: Darker frosted panel — `.ultraThinMaterial` with lower opacity

Add bottom separator to column header. Read resolved theme from `@AppStorage` + `@Environment(\.colorScheme)`.

### 4. Update `TaskCardView.swift`

Replace current `.regularMaterial` + `.glassEffect(.regular)` + full border with:
- **Top-edge accent stripe** (2.5pt, project colour) instead of full border
- **Universal**: `.ultraThinMaterial` background, subtle white border
- **Light**: Lighter material, white-tinted background, soft shadow
- **Dark**: Darker material, subtle border, inset highlight

Remove `.glassEffect(.regular)` — the layered materials on the gradient provide enough visual interest.

### 5. Update `SettingsView.swift`

Add an "Appearance" section (above General) with a Picker for theme selection:
- Follow System (default)
- Universal
- Light
- Dark

Use `@AppStorage("appTheme")` bound to the picker.

### 6. Apply background in `DashboardView.swift`

Add `BoardBackground(theme:)` as a `.background` behind the `GeometryReader` content. This ensures both `KanbanBoardView` and `SingleColumnView` get the gradient.

## Files to modify

| File | Change |
|------|--------|
| `Transit/Transit/Models/AppTheme.swift` | **New** — theme enum + resolved theme |
| `Transit/Transit/Views/Dashboard/BoardBackground.swift` | **New** — gradient background view |
| `Transit/Transit/Views/Dashboard/TaskCardView.swift` | Update card styling per theme |
| `Transit/Transit/Views/Dashboard/ColumnView.swift` | Add frosted panel background per theme |
| `Transit/Transit/Views/Dashboard/DashboardView.swift` | Apply board background |
| `Transit/Transit/Views/Settings/SettingsView.swift` | Add appearance picker |

## Verification

1. `make build` — confirm it compiles for both iOS and macOS
2. `make lint` — SwiftLint passes
3. `make test-quick` — existing unit tests still pass
4. Manual: launch in simulator, check all 4 theme options render correctly, toggle system dark mode to verify "Follow System" works
