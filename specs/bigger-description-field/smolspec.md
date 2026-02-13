# Bigger Description Field

## Overview

The task description field in Transit's form views is too small — currently limited to 3-6 lines via `TextField(axis: .vertical)` with `.lineLimit(3...6)`. On iOS, the description field should fill the available vertical space using `TextEditor`. On macOS, the description field should also use `TextEditor` with a reasonable minimum height inside the existing `FormRow` Grid layout.

## Requirements

- The system MUST replace the description `TextField` with a `TextEditor` on both iOS and macOS in AddTaskSheet and TaskEditView
- The system MUST offer a `.large` presentation detent on AddTaskSheet (currently only `.medium`), defaulting to `.large` via a `@State` selection binding
- The system MUST add a `.large` presentation detent on TaskEditView (currently has no detent set, presented as a sheet from TaskDetailView)
- The system MUST preserve existing trim-to-nil save behaviour for empty descriptions
- The system MUST apply a placeholder style to the `TextEditor` when empty (TextEditor has no built-in placeholder like TextField does)
- The system MUST ensure the macOS `TextEditor` aligns correctly within the `FormRow` Grid layout (first text baseline alignment with the "Description" label)

## Implementation Approach

**Files to modify:**
- `Transit/Transit/Views/AddTask/AddTaskSheet.swift` — replace description TextField with TextEditor on both platforms, add `.large` detent with selection binding
- `Transit/Transit/Views/TaskDetail/TaskEditView.swift` — replace description TextField with TextEditor on both platforms, add presentation detent

**iOS approach:**
- Replace `TextField("Description", text: $taskDescription, axis: .vertical).lineLimit(3...6)` with a `TextEditor(text: $taskDescription)` using `.frame(maxHeight: .infinity)` to fill available space
- Move the description field into its own `Section` so it can expand independently of the other fields
- Use a ZStack overlay with `Text("Description").foregroundStyle(.secondary)` placeholder that hides when `taskDescription` is non-empty
- On AddTaskSheet, change `.presentationDetents([.medium])` to `.presentationDetents([.medium, .large], selection: $selectedDetent)` with `@State private var selectedDetent: PresentationDetent = .large`
- On TaskEditView, add `.presentationDetents([.medium, .large], selection: $selectedDetent)` with default `.large`

**macOS approach:**
- Replace `TextField("", text: $taskDescription, axis: .vertical).lineLimit(3...6)` with `TextEditor(text: $taskDescription)` inside the existing `FormRow`
- Apply `.frame(minHeight: 120)` to give a reasonable default size without dominating the form
- Use the same ZStack placeholder pattern as iOS
- May need padding or alignment adjustments to keep the "Description" label aligned with the first line of text in the editor

**Shared:**
- Follow existing platform split pattern (`#if os(iOS)` / `#if os(macOS)`)
- Both AddTaskSheet and TaskEditView use identical description field definitions today — keep them consistent after the change

**Out of Scope:**
- TaskDetailView (read-only `Text` already grows to fit content)
- Adding markdown or rich text support
- Changing the macOS Liquid Glass section structure

## Risks and Assumptions

- **Risk:** `TextEditor` inside a `Form` on iOS may not expand to fill space due to Form's own layout rules. **Mitigation:** If `Form` constrains the height, apply `.frame(minHeight: 200)` or move the TextEditor outside the Form into a separate VStack region.
- **Risk:** `TextEditor` inside `FormRow`/`Grid` on macOS may not align its first text baseline with the label. **Mitigation:** Adjust with `.padding(.top, ...)` offset or switch the Grid row to `.leading` alignment for that row only.
- **Assumption:** SwiftUI's `TextEditor` binding to a `String` state variable preserves the existing trim-on-save pattern without changes to the save logic.
- **Risk:** `TextEditor` has no built-in placeholder on either platform. **Mitigation:** Use a ZStack overlay placeholder that disappears on input.
