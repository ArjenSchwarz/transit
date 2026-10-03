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

    @Test func advertisedBranches() throws {
        let data = try JSONEncoder().encode(MCPToolDefinitions.queryTasks.inputSchema)
        let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let branches = try #require(schema["oneOf"] as? [[String: Any]])
        #expect(branches.count == 2)
        #expect(branches.allSatisfy { $0["additionalProperties"] as? Bool == false })
        #expect(branches[0]["required"] as? [String] == ["detailLevel", "includeComments", "limit"])
        #expect(branches[1]["required"] as? [String] == ["cursor"])
    }
}
#endif
