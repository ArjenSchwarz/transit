import Foundation
import Testing
@testable import Transit

@MainActor
struct IntentErrorTests {

    // MARK: - Error Codes

    @Test func taskNotFoundCode() {
        let error = IntentError.taskNotFound(hint: "No task with displayId 42")
        #expect(error.code == "TASK_NOT_FOUND")
    }

    @Test func projectNotFoundCode() {
        let error = IntentError.projectNotFound(hint: "No project named Foo")
        #expect(error.code == "PROJECT_NOT_FOUND")
    }

    @Test func ambiguousProjectCode() {
        let error = IntentError.ambiguousProject(hint: "Multiple projects match")
        #expect(error.code == "AMBIGUOUS_PROJECT")
    }

    @Test func invalidStatusCode() {
        let error = IntentError.invalidStatus(hint: "Unknown status: flying")
        #expect(error.code == "INVALID_STATUS")
    }

    @Test func invalidTypeCode() {
        let error = IntentError.invalidType(hint: "Unknown type: epic")
        #expect(error.code == "INVALID_TYPE")
    }

    @Test func invalidInputCode() {
        let error = IntentError.invalidInput(hint: "Missing required field: name")
        #expect(error.code == "INVALID_INPUT")
    }

    // MARK: - Hint Property

    @Test func hintReturnsAssociatedValue() {
        let message = "Task T-99 not found in project Alpha"
        let error = IntentError.taskNotFound(hint: message)
        #expect(error.hint == message)
    }

    // MARK: - JSON Structure

    @Test func jsonProducesValidJSON() throws {
        let error = IntentError.invalidInput(hint: "Missing required field: name")
        let data = try #require(error.json.data(using: .utf8))
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: String]
        )
        #expect(parsed["error"] == "INVALID_INPUT")
        #expect(parsed["hint"] == "Missing required field: name")
    }

    @Test func jsonContainsBothKeys() throws {
        let error = IntentError.projectNotFound(hint: "No match")
        let data = try #require(error.json.data(using: .utf8))
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: String]
        )
        #expect(parsed.count == 2)
        #expect(parsed.keys.contains("error"))
        #expect(parsed.keys.contains("hint"))
    }

    // MARK: - Special Character Escaping

    @Test func jsonEscapesQuotes() throws {
        let error = IntentError.invalidInput(hint: "Expected \"name\" field")
        let data = try #require(error.json.data(using: .utf8))
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: String]
        )
        #expect(parsed["hint"] == "Expected \"name\" field")
    }

    @Test func jsonEscapesBackslashes() throws {
        let error = IntentError.invalidInput(hint: "Path: C:\\Users\\test")
        let data = try #require(error.json.data(using: .utf8))
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: String]
        )
        #expect(parsed["hint"] == "Path: C:\\Users\\test")
    }

    @Test func jsonHandlesUnicode() throws {
        let error = IntentError.invalidInput(hint: "Name contains emoji: \u{1F680}")
        let data = try #require(error.json.data(using: .utf8))
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: String]
        )
        #expect(parsed["hint"] == "Name contains emoji: \u{1F680}")
    }
}
