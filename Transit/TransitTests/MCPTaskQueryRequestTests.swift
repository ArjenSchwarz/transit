#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor
struct MCPTaskQueryRequestTests {
    private var options: [String: Any] {
        ["detailLevel": "full", "includeComments": false, "limit": 100]
    }

    @Test func initialAndContinuation() throws {
        _ = try MCPTaskQueryRequest.parse(options)
        _ = try MCPTaskQueryRequest.parse(["cursor": UUID().uuidString])
        #expect(throws: (any Error).self) { try MCPTaskQueryRequest.parse([:]) }
    }

    @Test func invalidOptionsAndSelectors() {
        let invalid: [[String: Any]] = [
            ["limit": 0], ["limit": 101], ["limit": true], ["limit": 1.5],
            ["detailLevel": "other"], ["detailLevel": NSNull()],
            ["includeComments": 1], ["includeComments": NSNull()],
            ["taskIds": []], ["taskIds": ["bad"]], ["displayIds": [true]],
            ["displayIds": [1.5]], ["displayIds": Array(repeating: 1, count: 101)],
            ["displayId": 1, "displayIds": [1]], ["taskIds": [UUID().uuidString], "search": ""],
            ["unknown": false], ["cursor": UUID().uuidString]
        ]
        for fields in invalid {
            #expect(throws: (any Error).self) {
                try MCPTaskQueryRequest.parse(options.merging(fields) { _, new in new })
            }
        }
        for key in options.keys {
            var missing = options
            missing.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try MCPTaskQueryRequest.parse(missing) }
        }
    }

    @Test func integralIDsAndBoundaries() throws {
        for count in [1, 100] {
            _ = try MCPTaskQueryRequest.parse(options.merging([
                "displayIds": Array(repeating: -1.0, count: count)
            ]) { _, new in new })
        }
        _ = try MCPTaskQueryRequest.parse(options.merging(["limit": 1.0]) { _, new in new })
    }

    @Test func malformedCursorHasRestartGuidance() throws {
        for cursor: Any in [42, NSNull(), "", "bad"] {
            do {
                _ = try MCPTaskQueryRequest.parse(["cursor": cursor])
                Issue.record("Malformed cursor was accepted")
            } catch let error as MCPTaskQueryError {
                #expect(error.code == "INVALID_CURSOR")
                #expect(error.message.contains("start a new query"))
            }
        }
    }

    @Test func cursorWithOtherFieldsIsInvalidInput() throws {
        for cursor: Any in [UUID().uuidString, 42, NSNull()] {
            do {
                _ = try MCPTaskQueryRequest.parse(["cursor": cursor, "limit": 1])
                Issue.record("Cursor with query options was accepted")
            } catch let error as MCPTaskQueryError {
                #expect(error.code == "INVALID_INPUT")
            }
        }
    }

    @Test func advertisedBranches() throws {
        let data = try JSONEncoder().encode(MCPToolDefinitions.queryTasks.inputSchema)
        let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let branches = try #require(schema["oneOf"] as? [[String: Any]])
        #expect(branches.count == 3)
        #expect(branches.allSatisfy { $0["additionalProperties"] as? Bool == false })
        #expect(branches[0]["required"] as? [String] == ["detailLevel", "includeComments", "limit"])
        #expect(branches[1]["required"] as? [String] == ["cursor"])
        #expect(branches[2]["required"] as? [String] == ["snapshotId", "detailLevel", "includeComments", "limit"])
        let ordinary = try #require(branches[0]["properties"] as? [String: Any])
        let continuation = try #require(branches[1]["properties"] as? [String: Any])
        let snapshot = try #require(branches[2]["properties"] as? [String: Any])
        #expect(ordinary["cursor"] == nil && ordinary["snapshotId"] == nil)
        #expect(ordinary["detailLevel"] != nil && ordinary["includeComments"] != nil
            && ordinary["limit"] != nil)
        #expect(Set(continuation.keys) == Set(["cursor", "readPolicy"]))
        #expect(Set(snapshot.keys) == Set([
            "snapshotId", "detailLevel", "includeComments", "limit", "projectId", "status"
        ]))
        #expect((snapshot["includeComments"] as? [String: Any])?["const"] as? Bool == false)
    }
}
#endif
