import Foundation
import Testing
@testable import Transit

struct IntentErrorTests {
    @Test
    func allErrorCodesAreStable() {
        #expect(IntentError.invalidInput(hint: "x").code == "INVALID_INPUT")
        #expect(IntentError.invalidType(hint: "x").code == "INVALID_TYPE")
        #expect(IntentError.projectNotFound(hint: "x").code == "PROJECT_NOT_FOUND")
        #expect(IntentError.ambiguousProject(hint: "x").code == "AMBIGUOUS_PROJECT")
        #expect(IntentError.taskNotFound(hint: "x").code == "TASK_NOT_FOUND")
        #expect(IntentError.invalidStatus(hint: "x").code == "INVALID_STATUS")
    }

    @Test
    func responseIsJSONWithExpectedShape() throws {
        let json = IntentError.invalidType(hint: "Type should be bug").response
        let object = try parseJSONObject(json)

        #expect(object["ok"] as? Bool == false)
        let error = object["error"] as? [String: Any]
        #expect(error?["code"] as? String == "INVALID_TYPE")
        #expect(error?["hint"] as? String == "Type should be bug")
    }

    @Test
    func specialCharactersAreEscapedByJSONSerialization() throws {
        let hint = #"Use "type": "feature"\nPath: C:\tmp\input.json"#
        let json = IntentError.invalidInput(hint: hint).response

        #expect(json.contains(#"\"type\": \"feature\""#))
        #expect(json.contains(#"\\n"#))
        #expect(json.contains(#"C:\\tmp\\input.json"#))

        let parsed = try parseJSONObject(json)
        let error = parsed["error"] as? [String: Any]
        #expect(error?["hint"] as? String == hint)
    }
}

private func parseJSONObject(_ json: String) throws -> [String: Any] {
    let data = try #require(json.data(using: .utf8))
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}
