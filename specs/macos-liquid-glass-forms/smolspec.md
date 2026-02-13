# macOS Liquid Glass Forms

## Overview

Apply the `swiftui-forms` skill (Grid + FormRow + LiquidGlassSection) to all form views on macOS. iOS layouts stay unchanged. TaskEditView is already done and serves as the reference implementation.

## Requirements

- All Form-based views MUST use the Liquid Glass Grid layout on macOS (`#if os(macOS)`)
- All Form-based views MUST keep the existing iOS Form layout unchanged
- Shared components used by both platforms MUST emit platform-adaptive content (iOS: `Section` wrapper, macOS: bare content)
- Platform-specific computed properties MUST be wrapped in `#if os()` blocks (not just the call site in `body`)
- The `swiftui-forms` skill MUST be followed for layout, sizing, and glass modifier usage

## Views to Convert

### 1. TaskEditView (DONE — reference implementation)
**File:** `Views/TaskDetail/TaskEditView.swift`
- macOS: ScrollView > VStack > LiquidGlassSection containers, Grid + FormRow for fields
- iOS: unchanged Form

### 2. TaskDetailView (read-only detail sheet)
**File:** `Views/TaskDetail/TaskDetailView.swift`
- Currently: `Form` with `LabeledContent` rows for name/type/status/project, optional description section, metadata section, action buttons (abandon/restore)
- macOS layout: ScrollView > VStack with LiquidGlassSection containers
  - "Details" section: Grid + FormRow for name, type (TypeBadge), status, project (color dot + name) — all read-only `Text`/views, no form controls
  - "Description" section: conditional, plain Text in a LiquidGlassSection
  - "Metadata" section: MetadataSection (already platform-adaptive) in LiquidGlassSection
  - "Actions" section: abandon/restore button in LiquidGlassSection
- Toolbar: keep share + edit buttons as-is, just guard `navigationBarTitleDisplayMode` with `#if os(iOS)`
- Note: this view already has `#if os(iOS)` for `navigationBarTitleDisplayMode` — just needs the Form → Grid conversion

### 3. AddTaskSheet (new task creation)
**File:** `Views/AddTask/AddTaskSheet.swift`
- Currently: `Form` with project picker, name, description, type picker. Empty state when no projects.
- macOS layout: ScrollView > VStack with LiquidGlassSection containers
  - "Task" section: Grid + FormRow for project picker, name, description
  - "Type" section: Grid + FormRow for type picker
  - Empty state view unchanged (platform-independent)
- Toolbar: Save button stays in toolbar, guard `navigationBarTitleDisplayMode` with `#if os(iOS)`
- Note: `navigationBarTitleDisplayMode` already guarded — the `taskForm` computed property needs the `#if os()` split

### 4. ProjectEditView (project create/edit)
**File:** `Views/Settings/ProjectEditView.swift`
- Currently: `Form` with name, description, git repo URL, color picker. Dual-purpose (create/edit).
- macOS layout: ScrollView > VStack with LiquidGlassSection containers
  - "Details" section: Grid + FormRow for name, description, git repo URL
  - "Appearance" section: Grid + FormRow for ColorPicker
- Toolbar: Save button stays in toolbar, guard `navigationBarTitleDisplayMode` with `#if os(iOS)`
- Note: `textInputAutocapitalization` already guarded with `#if os(iOS)`, but `navigationBarTitleDisplayMode` is at the Form level and needs the property split
- Note: this view is presented as a sheet (create) or pushed (edit) — the macOS layout works for both contexts

## Shared Components

### FormRow (`Views/Shared/FormRow.swift`) — DONE
- GridRow with right-aligned label + content with `.frame(maxWidth: .infinity, alignment: .leading)`

### LiquidGlassSection (`Views/Shared/LiquidGlassSection.swift`) — DONE
- VStack with headline title + `.background { RoundedRectangle.glassEffect(.regular, in:) }`

### MetadataSection (`Views/Shared/MetadataSection.swift`) — DONE
- Platform-adaptive: iOS wraps in `Section("Metadata")`, macOS emits bare content

## Implementation Approach

Each view follows the same pattern established in TaskEditView:

1. Split `body` into `#if os(macOS)` / `#else` branches calling separate computed properties
2. Wrap iOS computed properties in `#if os(iOS)` / `#endif`
3. Wrap macOS computed properties in `#if os(macOS)` / `#endif`
4. macOS property: ScrollView > VStack(spacing: 28) > LiquidGlassSection > Grid + FormRow
5. `labelWidth` sized to longest label in each view (~90 for short labels)
6. Text fields fill row width, pickers use `.fixedSize()`, no maxWidth constraints
7. Shared functions (save, load) stay outside `#if os()` blocks

## Verification

1. `make build` — both platforms
2. `make lint` — passes
3. `make test-quick` — unit tests pass
4. Manual: each view on macOS shows Grid layout with glass sections
5. Manual: each view on iOS looks identical to current behaviour
