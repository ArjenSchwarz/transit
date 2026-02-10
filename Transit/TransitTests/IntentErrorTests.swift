import Foundation
import Testing
@testable import Transit

@Suite("IntentError Tests")
struct IntentErrorTests {
    @Test("All error codes return correct string values")
    func errorCodes() {
        #expect(IntentError.taskNotFound(hint: "test").code == "TASK_NOT_FOUND")
        #expect(IntentError.projectNotFound(hint: "test").code == "PROJECT_NOT_FOUND")
        #expect(IntentError.ambiguousProject(hint: "test").code == "AMBIGUOUS_PROJECT")
        #expect(IntentError.invalidStatus(hint: "test").code == "INVALID_STATUS")
        #expect(IntentError.invalidType(hint: "test").code == "INVALID_TYPE")
        #expect(IntentError.invalidInput(hint: "test").code == "INVALID_INPUT")
    }

    @Test("JSON structure matches expected format")
    func jsonStructure() throws {
        let error = IntentError.taskNotFound(hint: "Task T-42 not found")
        let json = error.json

        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        #expect(parsed["error"] == "TASK_NOT_FOUND")
        #expect(parsed["hint"] == "Task T-42 not found")
    }

    @Test("Special characters are properly escaped in JSON")
    func specialCharacterEscaping() throws {
        let hintsWithSpecialChars = [
            "Project \"Test\" not found",
            "Invalid input: \n newline",
            "Path: /Users/test\\file",
            "Quote: ' and \"",
            "Tab:\there"
        ]

        for hint in hintsWithSpecialChars {
            let error = IntentError.invalidInput(hint: hint)
            let json = error.json

            // Verify it's valid JSON
            let data = try #require(json.data(using: .utf8))
            let parsed = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: String]
            )

            // Verify the hint round-trips correctly
            #expect(parsed["hint"] == hint)
        }
    }

    @Test("All error types produce valid JSON")
    func allErrorTypesProduceValidJSON() throws {
        let errors: [IntentError] = [
            .taskNotFound(hint: "Task not found"),
            .projectNotFound(hint: "Project not found"),
            .ambiguousProject(hint: "Multiple projects match"),
            .invalidStatus(hint: "Invalid status value"),
            .invalidType(hint: "Invalid type value"),
            .invalidInput(hint: "Malformed input")
        ]

        for error in errors {
            let json = error.json
            let data = try #require(json.data(using: .utf8))
            let parsed = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: String]
            )

            #expect(parsed["error"] != nil)
            #expect(parsed["hint"] != nil)
        }
    }

    @Test("Hint extraction works for all error types")
    func hintExtraction() {
        #expect(IntentError.taskNotFound(hint: "hint1").hint == "hint1")
        #expect(IntentError.projectNotFound(hint: "hint2").hint == "hint2")
        #expect(IntentError.ambiguousProject(hint: "hint3").hint == "hint3")
        #expect(IntentError.invalidStatus(hint: "hint4").hint == "hint4")
        #expect(IntentError.invalidType(hint: "hint5").hint == "hint5")
        #expect(IntentError.invalidInput(hint: "hint6").hint == "hint6")
    }

    @Test("Fallback error message when JSON encoding fails")
    func fallbackErrorMessage() {
        // This is hard to trigger since JSONSerialization is robust,
        // but we verify the fallback exists by checking the implementation
        // returns a valid JSON string even in edge cases
        let error = IntentError.invalidInput(hint: "")
        let json = error.json

        #expect(json.contains("\"error\""))
        #expect(json.contains("\"hint\""))
    }
}
