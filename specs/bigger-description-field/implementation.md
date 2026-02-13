# Implementation: Bigger Description Field

## Beginner Level

### What Changed
The task description input in Transit was too small — it was a text field limited to 3–6 lines. This change replaces it with a larger text editor that can grow to fill the available space, making it easier to write longer descriptions.

Two screens were updated: the "Add Task" sheet (where you create new tasks) and the "Edit Task" sheet (where you modify existing tasks). Both screens now open larger by default (large sheet size instead of medium), giving more room for the description.

### Why It Matters
When users need to write detailed task descriptions, a tiny text field forces awkward scrolling within a few lines. A larger editor makes the input feel natural and encourages better documentation of tasks.

### Key Concepts
- **TextEditor vs TextField**: `TextField` is a single-line (or limited multi-line) input. `TextEditor` is a full multi-line text area, like a notepad. TextEditor has no built-in placeholder text, so a workaround is needed.
- **Presentation detent**: Controls how tall a sheet (slide-up panel on iOS) is. `.medium` covers about half the screen; `.large` covers most of it.
- **ZStack placeholder**: Since `TextEditor` doesn't show greyed-out hint text like `TextField` does, a `Text("Description")` label is placed behind the editor using a `ZStack` and hidden when the user starts typing.

---

## Intermediate Level

### Changes Overview
Two view files modified:
- `AddTaskSheet.swift` — iOS and macOS forms for creating tasks
- `TaskEditView.swift` — iOS and macOS forms for editing tasks

Both follow the same pattern: platform-specific layouts via `#if os(iOS)` / `#if os(macOS)`.

### Implementation Approach

**iOS (both views):**
- Description moved from the fields `Section` into its own `Section` so Form layout allows independent vertical expansion
- `TextEditor(text: $taskDescription).frame(maxHeight: .infinity)` fills available space
- ZStack overlay provides placeholder text when empty
- `.presentationDetents([.medium, .large], selection: $selectedDetent)` with `@State private var selectedDetent: PresentationDetent = .large` defaults the sheet to large

**macOS (both views):**
- `TextEditor` replaces `TextField` inside the existing `FormRow` Grid layout
- `.frame(minHeight: 120)` provides a reasonable default size
- `.scrollContentBackground(.hidden)` removes the default TextEditor background so it blends with the Liquid Glass section
- Same ZStack placeholder pattern as iOS

**Preserved behavior:**
- Save functions unchanged — both trim whitespace and convert empty strings to `nil`, which is how SwiftData stores absent descriptions

### Trade-offs
- **TextEditor has no native placeholder** — the ZStack overlay is the standard SwiftUI workaround. It adds a few lines of code per usage but is simple and reliable.
- **iOS doesn't use `.scrollContentBackground(.hidden)`** — inside a `Form` `Section`, the default background integrates naturally. On macOS, hiding it is needed because the `LiquidGlassSection` provides its own background.
- **No extraction into a shared component** — the placeholder TextEditor pattern appears 4 times (2 views × 2 platforms). A shared view could reduce duplication, but the spec explicitly called for keeping changes minimal and consistent between the two views. The pattern is simple enough that duplication is acceptable.

---

## Expert Level

### Technical Deep Dive
The change is straightforward — swap `TextField(axis: .vertical)` for `TextEditor` with a placeholder overlay. Key decisions:

1. **Separate Section on iOS**: Moving the TextEditor to its own `Section` is necessary because `Form` constrains row heights. A TextEditor sharing a Section with other fields would be limited by the Section's layout. In its own Section with `.frame(maxHeight: .infinity)`, it expands to fill remaining sheet space.

2. **`scrollContentBackground(.hidden)` on macOS only**: TextEditor renders its own background. On macOS, this conflicts with the `LiquidGlassSection` glass effect. On iOS, the Form's Section styling handles it naturally.

3. **Detent selection binding**: Using `@State private var selectedDetent` with a default of `.large` means the sheet opens large. The user can still drag down to `.medium` if they prefer. This is a `@State` rather than persisted preference — it resets each time the sheet opens.

### Architecture Impact
Minimal. No new types, no logic changes, no data model changes. The save functions' trim-to-nil behavior works identically with `TextEditor`'s `String` binding as it did with `TextField`'s.

### Potential Issues
- **iOS Form expansion**: If a future iOS version changes how `Form` handles `Section` heights, the `.frame(maxHeight: .infinity)` approach might not expand as expected. The spec notes `.frame(minHeight: 200)` as a fallback mitigation.
- **Placeholder alignment**: The `.padding(.top, 8).padding(.leading, 4)` on the placeholder text is hand-tuned to align with TextEditor's internal text offset. This could drift across OS versions, though it's a common pattern.

---

## Completeness Assessment

### Fully Implemented
- TextEditor replacement on both platforms in both AddTaskSheet and TaskEditView
- `.large` presentation detent with `.medium` option on both views
- ZStack placeholder overlay on all four instances (2 views × 2 platforms)
- Trim-to-nil save behavior preserved (no changes needed — existing logic works)
- macOS TextEditor alignment in FormRow Grid layout via `leadingFirstTextBaseline` grid alignment
- CHANGELOG.md updated

### Partially Implemented
None.

### Missing
None. All six spec requirements are addressed.
