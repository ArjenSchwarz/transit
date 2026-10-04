#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskRequestBoundaryTests {
    private typealias Fixture = MCPBatchTaskRequestFixtures

    @Test(arguments: ["1.0", "1e0", "10e-1", "-0.0", "0e999999999999999999999", "9007199254740993",
                      "9223372036854775807", "-9223372036854775808", "1.0000000000000000000000001",
                      "0.9999999999999999999999999", "1e-999", "-1e-999", "9223372036854775808",
                      "-9223372036854775809", "1e999999999999999999999"])
    func exactIntegerBridgeRejectsRoundedFractionsAndRangeOverflow(lexeme: String) throws {
        let text = """
        {"mode":"execute","items":[{"itemId":"caller","operation":"update_task","arguments":{
          "taskId":"\(Fixture.taskID(0))","idempotencyKey":"key","expectedRevision":"\(Fixture.revision)",
          "milestoneDisplayId":\(lexeme)}}]}
        """
        let document = try MCPJSONDocument.parse(text)
        let expected: [String: Int] = ["1.0": 1, "1e0": 1, "10e-1": 1, "-0.0": 0,
                                     "0e999999999999999999999": 0, "9007199254740993": 9_007_199_254_740_993,
                                     "9223372036854775807": Int.max, "-9223372036854775808": Int.min]
        if let integer = expected[lexeme] {
            let item = try #require(Fixture.valid(document).items.first)
            #expect(item.command.arguments["milestoneDisplayId"] as? Int == integer)
            guard case .number(let number) = Fixture.field("milestoneDisplayId", in: item.originalArguments) else {
                Issue.record("Lossless original numeric evidence required"); return
            }
            #expect(number.lexeme == lexeme)
        } else {
            try Fixture.invalid(document, index: 0, itemId: "caller", field: "milestoneDisplayId")
        }
    }

    @Test(arguments: ["collision", "singleDecomposed"])
    func metadataNamesMustSurviveExistingDictionaryBridgeWithoutLoss(kind: String) throws {
        let members = kind == "collision" ? #""é":"first","e\u0301":"second""# : #""e\u0301":" untouched ""#
        let text = """
        {"mode":"execute","items":[{"itemId":"caller","operation":"update_task","arguments":{
          "taskId":"\(Fixture.taskID(0))","idempotencyKey":"key","expectedRevision":"\(Fixture.revision)",
          "metadata":{\(members)}}}]}
        """
        let document = try MCPJSONDocument.parse(text)
        if kind == "collision" {
            try Fixture.invalid(document, index: 0, itemId: "caller", field: "metadata")
        } else {
            let item = try #require(Fixture.valid(document).items.first)
            let metadata = try #require(item.command.arguments["metadata"] as? [String: String])
            let key = try #require(metadata.keys.first)
            #expect(key.utf8.elementsEqual("e\u{0301}".utf8))
            #expect(metadata[key]?.utf8.elementsEqual(" untouched ".utf8) == true)
            #expect(metadata.count == 1)
        }
        #expect(document.originalUTF8.elementsEqual(text.utf8))
    }

    @Test(arguments: ["idempotencyKey", "unknowné", "unknowne\u{0301}"])
    func structuralFieldNamesCannotMasqueradeThroughCanonicalEquality(name: String) throws {
        let text = """
        {"mode":"execute","items":[{"itemId":"caller.0","operation":"update_task","arguments":{
          "taskId":"\(Fixture.taskID(0))","idempotencyKey":"key","expectedRevision":"\(Fixture.revision)",
          "\(name)":"key"}}]}
        """
        let document = try MCPJSONDocument.parse(text)
        switch try MCPBatchTaskRequest.parse(document) {
        case .valid: Issue.record("Closed structural names require scalar-exact matching")
        case .invalid(let diagnostics):
            #expect(diagnostics.contains {
                $0.index == 0 && $0.itemId == "caller.0" && $0.code == "INVALID_INPUT" &&
                    $0.field.utf8.elementsEqual(name.utf8)
            })
        }
    }

    @Test(arguments: ["root", "item", "arguments"])
    func rawValueSeamStillRejectsDuplicateStructuralMembers(location: String) throws {
        let source = try Fixture.document(items: [Fixture.item()]).value
        func duplicated(_ value: MCPJSONValue, name: String) throws -> MCPJSONValue {
            guard case .object(var members) = value else { throw MCPResultBoundaryError.unsupportedEvidence }
            let original = try #require(members.first { $0.name == name })
            members.append(original)
            return .object(members)
        }
        let changed: MCPJSONValue
        let field: String
        if location == "root" {
            changed = try duplicated(source, name: "mode"); field = "mode"
        } else {
            guard case .object(var root) = source else { throw MCPResultBoundaryError.unsupportedEvidence }
            let item = try #require(Fixture.array(Fixture.field("items", in: source)).first)
            let mutated: MCPJSONValue
            if location == "item" { mutated = try duplicated(item, name: "itemId"); field = "itemId" } else {
                guard case .object(var members) = item else { throw MCPResultBoundaryError.unsupportedEvidence }
                let arguments = try #require(Fixture.field("arguments", in: item))
                members.removeAll { $0.name == "arguments" }
                members.append(.init(name: "arguments", value: try duplicated(arguments, name: "taskId")))
                mutated = .object(members); field = "taskId"
            }
            root.removeAll { $0.name == "items" }
            root.append(.init(name: "items", value: .array([mutated])))
            changed = .object(root)
        }
        switch try MCPBatchTaskRequest.parse(validatedValue: changed) {
        case .valid: Issue.record("Raw immutable argument seam cannot bypass duplicate member rejection")
        case .invalid(let diagnostics):
            #expect(diagnostics.contains { $0.field == field && $0.code == "INVALID_INPUT" })
        }
    }
}
#endif
