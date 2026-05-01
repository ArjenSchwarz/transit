import Foundation
import Testing
@testable import Transit

/// Regression tests for T-1063: task and milestone form views previously trimmed only
/// `.whitespaces`, leaving newline characters in pasted content. The fix routes form-side
/// trimming through `String.trimmedForFormInput()`, which uses `.whitespacesAndNewlines`
/// to align with the App Intent, MCP, and service layers.
///
/// These tests capture the expected trimming contract that the form views' save paths
/// depend on. If `trimmedForFormInput()` ever stops stripping newlines, AddTaskSheet,
/// TaskEditView, and MilestoneEditView would silently regress to the old behaviour.
@MainActor @Suite(.serialized)
struct FormInputTrimTests {

    // MARK: - Newlines must be trimmed

    @Test func trimStripsLeadingAndTrailingNewlines() {
        let input = "\n\nMy Task\n\n"
        #expect(input.trimmedForFormInput() == "My Task")
    }

    @Test func trimStripsCarriageReturnAndLineFeedMix() {
        let input = "\r\nMy Task\r\n"
        #expect(input.trimmedForFormInput() == "My Task")
    }

    @Test func trimStripsMixedSpacesAndNewlines() {
        let input = "  \n  Pasted Task Name  \n  "
        #expect(input.trimmedForFormInput() == "Pasted Task Name")
    }

    @Test func trimStripsTabsAndNewlines() {
        let input = "\t\n  Description body  \n\t"
        #expect(input.trimmedForFormInput() == "Description body")
    }

    // MARK: - Internal whitespace is preserved

    @Test func trimPreservesInternalNewlines() {
        let input = "\n\nFirst line\nSecond line\n\n"
        #expect(input.trimmedForFormInput() == "First line\nSecond line")
    }

    @Test func trimPreservesInternalSpaces() {
        let input = "  hello world  "
        #expect(input.trimmedForFormInput() == "hello world")
    }

    // MARK: - canSave guard rejects newline-only input

    /// AddTaskSheet, TaskEditView, and MilestoneEditView all gate their Save button on
    /// `!name.trimmedForFormInput().isEmpty`. A newline-only paste must therefore disable
    /// Save just as a space-only paste does.
    @Test func newlineOnlyInputIsTreatedAsEmpty() {
        #expect("\n".trimmedForFormInput().isEmpty)
        #expect("\n\n\n".trimmedForFormInput().isEmpty)
        #expect("\r\n".trimmedForFormInput().isEmpty)
        #expect(" \n \t \r\n ".trimmedForFormInput().isEmpty)
    }

    // MARK: - Empty / no-op cases

    @Test func trimOfEmptyStringIsEmpty() {
        #expect("".trimmedForFormInput().isEmpty)
    }

    @Test func trimOfPlainStringIsUnchanged() {
        #expect("Already clean".trimmedForFormInput() == "Already clean")
    }
}
