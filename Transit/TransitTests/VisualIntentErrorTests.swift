import Foundation
import Testing
@testable import Transit

@MainActor
struct VisualIntentErrorTests {

    // MARK: - Error Description

    @Test func noProjectsErrorDescription() {
        let error = VisualIntentError.noProjects
        #expect(error.errorDescription == "No projects exist. Create a project in Transit first.")
    }

    @Test func invalidInputErrorDescription() {
        let error = VisualIntentError.invalidInput("Name is empty")
        #expect(error.errorDescription == "Invalid input: Name is empty")
    }

    @Test func invalidDateErrorDescription() {
        let error = VisualIntentError.invalidDate("Expected YYYY-MM-DD format")
        #expect(error.errorDescription == "Invalid date: Expected YYYY-MM-DD format")
    }

    @Test func projectNotFoundErrorDescription() {
        let error = VisualIntentError.projectNotFound("Project Alpha no longer exists")
        #expect(error.errorDescription == "Project not found: Project Alpha no longer exists")
    }

    @Test func taskNotFoundErrorDescription() {
        let error = VisualIntentError.taskNotFound("Task T-42 not found")
        #expect(error.errorDescription == "Task not found: Task T-42 not found")
    }

    @Test func taskCreationFailedErrorDescription() {
        let error = VisualIntentError.taskCreationFailed("Database write failed")
        #expect(error.errorDescription == "Task creation failed: Database write failed")
    }

    // MARK: - Failure Reason

    @Test func noProjectsFailureReason() {
        let error = VisualIntentError.noProjects
        #expect(error.failureReason == "Transit requires at least one project to create tasks.")
    }

    @Test func invalidInputFailureReason() {
        let error = VisualIntentError.invalidInput("test")
        #expect(error.failureReason == "The provided input is missing required fields or contains invalid data.")
    }

    @Test func invalidDateFailureReason() {
        let error = VisualIntentError.invalidDate("test")
        #expect(error.failureReason == "The date format is incorrect or the date range is invalid.")
    }

    @Test func projectNotFoundFailureReason() {
        let error = VisualIntentError.projectNotFound("test")
        #expect(error.failureReason == "The selected project no longer exists in the database.")
    }

    @Test func taskNotFoundFailureReason() {
        let error = VisualIntentError.taskNotFound("test")
        #expect(error.failureReason == "The specified task could not be found.")
    }

    @Test func taskCreationFailedFailureReason() {
        let error = VisualIntentError.taskCreationFailed("test")
        #expect(error.failureReason == "An unexpected error occurred while creating the task.")
    }

    // MARK: - Recovery Suggestion

    @Test func noProjectsRecoverySuggestion() {
        let error = VisualIntentError.noProjects
        #expect(error.recoverySuggestion == "Open Transit and create a project before using this Shortcut.")
    }

    @Test func invalidInputRecoverySuggestion() {
        let error = VisualIntentError.invalidInput("test")
        #expect(error.recoverySuggestion == "Check that all required fields are filled in correctly.")
    }

    @Test func invalidDateRecoverySuggestion() {
        let error = VisualIntentError.invalidDate("test")
        #expect(error.recoverySuggestion == "Verify the date format (YYYY-MM-DD) or select a valid date range.")
    }

    @Test func projectNotFoundRecoverySuggestion() {
        let error = VisualIntentError.projectNotFound("test")
        #expect(error.recoverySuggestion == "Select a different project or create a new one in the app.")
    }

    @Test func taskNotFoundRecoverySuggestion() {
        let error = VisualIntentError.taskNotFound("test")
        #expect(error.recoverySuggestion == "The task may have been deleted. Try searching for it in the app.")
    }

    @Test func taskCreationFailedRecoverySuggestion() {
        let error = VisualIntentError.taskCreationFailed("test")
        #expect(error.recoverySuggestion == "Check that the app has sufficient storage and try again. If the problem persists, restart the app.")
    }

    // MARK: - LocalizedError Protocol Conformance

    @Test func errorConformsToLocalizedError() {
        let error: any LocalizedError = VisualIntentError.noProjects
        #expect(error.errorDescription != nil)
        #expect(error.failureReason != nil)
        #expect(error.recoverySuggestion != nil)
    }

    // MARK: - Error Codes

    @Test func noProjectsErrorCode() {
        let error = VisualIntentError.noProjects
        #expect(error.code == "NO_PROJECTS")
    }

    @Test func invalidInputErrorCode() {
        let error = VisualIntentError.invalidInput("test")
        #expect(error.code == "INVALID_INPUT")
    }

    @Test func invalidDateErrorCode() {
        let error = VisualIntentError.invalidDate("test")
        #expect(error.code == "INVALID_DATE")
    }

    @Test func projectNotFoundErrorCode() {
        let error = VisualIntentError.projectNotFound("test")
        #expect(error.code == "PROJECT_NOT_FOUND")
    }

    @Test func taskNotFoundErrorCode() {
        let error = VisualIntentError.taskNotFound("test")
        #expect(error.code == "TASK_NOT_FOUND")
    }

    @Test func taskCreationFailedErrorCode() {
        let error = VisualIntentError.taskCreationFailed("test")
        #expect(error.code == "TASK_CREATION_FAILED")
    }

    // MARK: - Associated Values

    @Test func invalidInputPreservesHint() {
        let hint = "Name field cannot be empty"
        let error = VisualIntentError.invalidInput(hint)
        if case .invalidInput(let preservedHint) = error {
            #expect(preservedHint == hint)
        } else {
            Issue.record("Expected invalidInput case")
        }
    }

    @Test func invalidDatePreservesHint() {
        let hint = "Date must be in YYYY-MM-DD format"
        let error = VisualIntentError.invalidDate(hint)
        if case .invalidDate(let preservedHint) = error {
            #expect(preservedHint == hint)
        } else {
            Issue.record("Expected invalidDate case")
        }
    }

    @Test func projectNotFoundPreservesHint() {
        let hint = "Project with ID abc123 not found"
        let error = VisualIntentError.projectNotFound(hint)
        if case .projectNotFound(let preservedHint) = error {
            #expect(preservedHint == hint)
        } else {
            Issue.record("Expected projectNotFound case")
        }
    }

    @Test func taskNotFoundPreservesHint() {
        let hint = "Task with ID def456 not found"
        let error = VisualIntentError.taskNotFound(hint)
        if case .taskNotFound(let preservedHint) = error {
            #expect(preservedHint == hint)
        } else {
            Issue.record("Expected taskNotFound case")
        }
    }

    @Test func taskCreationFailedPreservesHint() {
        let hint = "SwiftData save failed"
        let error = VisualIntentError.taskCreationFailed(hint)
        if case .taskCreationFailed(let preservedHint) = error {
            #expect(preservedHint == hint)
        } else {
            Issue.record("Expected taskCreationFailed case")
        }
    }

    // MARK: - Special Characters in Hints

    @Test func hintsWithQuotesArePreserved() {
        let hint = "Expected \"name\" field"
        let error = VisualIntentError.invalidInput(hint)
        #expect(error.errorDescription?.contains(hint) == true)
    }

    @Test func hintsWithUnicodeArePreserved() {
        let hint = "Project name contains emoji: \u{1F680}"
        let error = VisualIntentError.projectNotFound(hint)
        #expect(error.errorDescription?.contains(hint) == true)
    }

    @Test func hintsWithNewlinesArePreserved() {
        let hint = "Multiple errors:\n- Name is empty\n- Type is invalid"
        let error = VisualIntentError.invalidInput(hint)
        #expect(error.errorDescription?.contains(hint) == true)
    }
}
