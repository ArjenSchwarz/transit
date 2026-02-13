---
references:
    - specs/bigger-description-field/smolspec.md
---
# Bigger Description Field

## AddTaskSheet

- [x] 1. iOS: Replace description TextField with TextEditor that fills available space in its own Section

- [x] 2. macOS: Replace description TextField with TextEditor using .frame(minHeight: 120) inside FormRow

- [x] 3. Add ZStack placeholder overlay ("Description" in .secondary) that hides when text is non-empty

- [x] 4. Change presentation detent to .large default with .medium option via @State selection binding

- [x] 5. Build succeeds on both platforms; TextEditor expands on iOS and aligns in Grid on macOS

## TaskEditView

- [x] 6. iOS: Replace description TextField with TextEditor that fills available space in its own Section

- [x] 7. macOS: Replace description TextField with TextEditor using .frame(minHeight: 120) inside FormRow

- [x] 8. Add ZStack placeholder overlay matching AddTaskSheet pattern

- [x] 9. Add .large presentation detent with .medium option via @State selection binding (currently has no detent)

- [x] 10. Build succeeds on both platforms; TextEditor expands on iOS and aligns in Grid on macOS

## Verification

- [x] 11. Trim-to-nil save behaviour preserved: empty TextEditor saves description as nil in both views
