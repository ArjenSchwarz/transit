import Testing
@testable import Transit

@Suite
struct VisualIntentErrorTests {
    @Test("error code mapping", arguments: [
        (VisualIntentError.noProjects, "NO_PROJECTS"),
        (VisualIntentError.invalidInput("bad"), "INVALID_INPUT"),
        (VisualIntentError.invalidDate("bad"), "INVALID_DATE"),
        (VisualIntentError.projectNotFound("bad"), "PROJECT_NOT_FOUND"),
        (VisualIntentError.taskNotFound("bad"), "TASK_NOT_FOUND"),
        (VisualIntentError.taskCreationFailed("bad"), "TASK_CREATION_FAILED")
    ])
    func codeMapping(error: VisualIntentError, expected: String) {
        #expect(error.code == expected)
    }

    @Test func noProjectsErrorContainsGuidance() {
        let error = VisualIntentError.noProjects
        #expect(error.errorDescription?.contains("Create a project") == true)
        #expect(error.recoverySuggestion?.contains("Open Transit") == true)
    }

    @Test func invalidInputIncludesHint() {
        let error = VisualIntentError.invalidInput("Name is required")
        #expect(error.errorDescription?.contains("Name is required") == true)
        #expect(error.failureReason != nil)
        #expect(error.recoverySuggestion != nil)
    }
}
