# Plan: Convert macOS Settings to Sidebar Navigation

## Context

The macOS Settings window uses a `Settings` scene with `NavigationStack`. Toolbar items (back buttons) render as centered floating Liquid Glass pills because the `Settings` scene doesn't create a proper `NSToolbar`. Apple's own System Settings uses sidebar navigation. We'll adopt the same pattern.

## Approach

Replace the single-ScrollView layout with `NavigationSplitView` — sidebar lists categories, detail column shows the selected category's content with its own `NavigationStack` for sub-navigation (project edit, milestone edit, license text).

## Files to Modify

1. **`Transit/Transit/Views/Settings/SettingsView.swift`** — Main restructure
2. **`Transit/Transit/TransitApp.swift`** — Simplify Settings scene
3. **`Transit/Transit/Views/Settings/ProjectEditView.swift`** — Remove custom toolbar back button (system back button works in NavigationSplitView detail)
4. **`Transit/Transit/Views/Settings/MilestoneEditView.swift`** — Same as above
5. **`Transit/Transit/Views/Settings/AcknowledgmentsView.swift`** — Remove `.toolbarBackgroundVisibility(.hidden)` from macOS layout

## Implementation Steps

### 1. Add `SettingsCategory` enum (SettingsView.swift)

```swift
#if os(macOS)
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance, projects, mcpServer, general, acknowledgments
    var id: String { rawValue }
    var title: String { /* Appearance, Projects, MCP Server, General, Acknowledgments */ }
    var icon: String { /* paintbrush, folder, network, gearshape, heart.text.square */ }
}
#endif
```

### 2. Restructure `macOSSettings` (SettingsView.swift)

Add state:
- `@State private var selectedCategory: SettingsCategory? = .appearance`
- `@State private var detailPath = NavigationPath()`

Replace the ScrollView with:
```swift
NavigationSplitView {
    List(selection: $selectedCategory) {
        ForEach(SettingsCategory.allCases) { category in
            Label(category.title, systemImage: category.icon)
                .tag(category)
        }
    }
    .navigationTitle("Settings")
} detail: {
    NavigationStack(path: $detailPath) {
        // switch on selectedCategory, render category content
        // .navigationDestination(for: NavigationDestination.self) { ... }
    }
}
.onChange(of: selectedCategory) { _, _ in
    detailPath = NavigationPath()  // pop to root on category change
}
```

### 3. Extract detail views per category

Each category's content is a ScrollView wrapping the existing `LiquidGlassSection` content (reusing `macOSAppearanceSection`, `macOSProjectsSection`, `macOSMCPSection`, `macOSGeneralSection`). Each gets:
- `.padding(32)`, `.frame(maxWidth: 760)`, `.frame(maxWidth: .infinity)`
- `.scrollContentBackground(.hidden)`, `.background { BoardBackground(theme: resolvedTheme) }`

For Acknowledgments: render `AcknowledgmentsView()` directly as the detail content.

### 4. Remove Acknowledgments from General section

The existing Acknowledgments NavigationLink in `macOSGeneralSection` is already moved out of the FormRow (issue 2 fix). Now remove it entirely since Acknowledgments is its own sidebar category.

### 5. Simplify TransitApp.swift Settings scene

Remove the `NavigationStack` and `navigationDestination` wrapper. SettingsView now owns its own navigation:

```swift
Settings {
    SettingsView()
        .preferredColorScheme(...)
        .environment(...)
        // ... all environment injection stays
}
```

### 6. Clean up sub-view toolbars

**ProjectEditView** and **MilestoneEditView** macOS layouts: Remove the custom `.toolbar { ToolbarItem(placement: .cancellationAction) { chevron.left } }` and `.navigationBarBackButtonHidden(isEditing)`. Inside `NavigationSplitView`'s detail `NavigationStack`, the system provides a proper back button.

**AcknowledgmentsView** macOS layout: Remove `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` — no longer needed inside `NavigationSplitView`.

**LicenseTextView** macOS layout: Same — remove `.toolbarBackgroundVisibility(.hidden)`.

### 7. Sheet for new projects

The `.sheet(isPresented: $showCreateProject)` stays on the detail content (or at the NavigationSplitView level). No change to the sheet pattern.

## What stays unchanged

- iOS layout (all `#if os(iOS)` blocks)
- NavigationDestination enum
- LiquidGlassSection, FormRow helpers
- DashboardView's SettingsLink entry point
- Content of each section (theme picker, MCP toggle, project list, etc.)

## Verification

1. `make build` — builds for both iOS and macOS
2. `make test-quick` — unit tests pass
3. `make lint` — no new violations
4. Manual: Cmd+Comma opens Settings with sidebar visible, Appearance selected by default
5. Manual: Clicking each sidebar category shows its content in the detail pane
6. Manual: Clicking a project pushes ProjectEditView with a working system back button
7. Manual: Acknowledgments → View Full License Text pushes LicenseTextView with working back button
8. Manual: Switching sidebar categories pops any pushed views
9. Manual: iOS settings navigation unchanged (push onto root NavigationStack)
