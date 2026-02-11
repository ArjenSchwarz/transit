import Foundation
import Testing
@testable import Transit

@MainActor
struct VisualIntentErrorTests {

    // MARK: - Error Descriptions

    @Test func noProjectsDescription() {
        let error = VisualIntentError.noProjects
        #expect(error.errorDescription == "No projects exist. Create a project in Transit first.")
    }

    @Test func invalidInputDescription() {
        let error = VisualIntentError.invalidInput("Task name cannot be empty")
        #expect(error.errorDescription == "Invalid input: Task name cannot be empty")
    }

    @Test func invalidDateDescription() {
        let error = VisualIntentError.invalidDate("Expected format YYYY-MM-DD")
        #expect(error.errorDescription == "Invalid date: Expected format YYYY-MM-DD")
    }

    @Test func projectNotFoundDescription() {
        let error = VisualIntentError.projectNotFound("Project was deleted")
        #expect(error.errorDescription == "Project not found: Project was deleted")
    }

    @Test func taskNotFoundDescription() {
        let error = VisualIntentError.taskNotFound("No task with that ID")
        #expect(error.errorDescription == "Task not found: No task with that ID")
    }

    @Test func taskCreationFailedDescription() {
        let error = VisualIntentError.taskCreationFailed("Database error")
        #expect(error.errorDescription == "Task creation failed: Database error")
    }

    // MARK: - Failure Reasons

    @Test func noProjectsFailureReason() {
        let error = VisualIntentError.noProjects
        #expect(error.failureReason == "Transit requires at least one project to create tasks.")
    }

    @Test func invalidInputFailureReason() {
        let error = VisualIntentError.invalidInput("any")
        #expect(error.failureReason == "The provided input is missing required fields or contains invalid data.")
    }

    // MARK: - Recovery Suggestions

    @Test func noProjectsRecoverySuggestion() {
        let error = VisualIntentError.noProjects
        #expect(error.recoverySuggestion == "Open Transit and create a project before using this Shortcut.")
    }

    @Test func invalidDateRecoverySuggestion() {
        let error = VisualIntentError.invalidDate("bad format")
        #expect(error.recoverySuggestion == "Verify the date format (YYYY-MM-DD) or select a valid date range.")
    }

    // MARK: - LocalizedError Conformance

    @Test func conformsToLocalizedError() {
        let error: any LocalizedError = VisualIntentError.noProjects
        #expect(error.errorDescription != nil)
        #expect(error.failureReason != nil)
        #expect(error.recoverySuggestion != nil)
    }

    // MARK: - All Cases Have Descriptions

    @Test func allCasesHaveErrorDescriptions() {
        let cases: [VisualIntentError] = [
            .noProjects,
            .invalidInput("test"),
            .invalidDate("test"),
            .projectNotFound("test"),
            .taskNotFound("test"),
            .taskCreationFailed("test")
        ]

        for error in cases {
            #expect(error.errorDescription != nil, "Missing errorDescription for \(error)")
            #expect(error.failureReason != nil, "Missing failureReason for \(error)")
            #expect(error.recoverySuggestion != nil, "Missing recoverySuggestion for \(error)")
        }
    }
}
