---
references:
    - specs/bigger-description-field/smolspec.md
---
# Bigger Description Field

## AddTaskSheet

- [ ] 1. iOS: Replace description TextField with TextEditor that fills available space in its own Section

- [ ] 2. macOS: Replace description TextField with TextEditor using .frame(minHeight: 120) inside FormRow

- [ ] 3. Add ZStack placeholder overlay ("Description" in .secondary) that hides when text is non-empty

- [ ] 4. Change presentation detent to .large default with .medium option via @State selection binding

- [ ] 5. Build succeeds on both platforms; TextEditor expands on iOS and aligns in Grid on macOS

## TaskEditView

- [ ] 6. iOS: Replace description TextField with TextEditor that fills available space in its own Section

- [ ] 7. macOS: Replace description TextField with TextEditor using .frame(minHeight: 120) inside FormRow

- [ ] 8. Add ZStack placeholder overlay matching AddTaskSheet pattern

- [ ] 9. Add .large presentation detent with .medium option via @State selection binding (currently has no detent)

- [ ] 10. Build succeeds on both platforms; TextEditor expands on iOS and aligns in Grid on macOS

## Verification

- [ ] 11. Trim-to-nil save behaviour preserved: empty TextEditor saves description as nil in both views
