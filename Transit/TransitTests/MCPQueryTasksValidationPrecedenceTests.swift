#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1816: Both legitimate missing-milestone paths must remain downstream of all
// query_tasks filter validation, so malformed input can never look like [].
@MainActor @Suite(.serialized)
struct MCPQueryTasksValidationPrecedenceTests {

    private struct MalformedFilter {
        let key: String
        let value: Any
        let expectedError: String
    }

    @Test func missingMilestonesDoNotMaskMalformedQueryFilters() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let missingMilestoneFilters: [[String: Any]] = [
            ["milestone": "does-not-exist"],
            ["milestoneDisplayId": 999]
        ]
        let malformedFilters = [
            MalformedFilter(key: "status", value: "not-a-status", expectedError: "Invalid status: not-a-status"),
            MalformedFilter(
                key: "not_status", value: "not-a-status", expectedError: "Invalid not_status: not-a-status"
            ),
            MalformedFilter(key: "type", value: "not-a-type", expectedError: "Invalid type: not-a-type"),
            MalformedFilter(
                key: "priority", value: "not-a-priority", expectedError: "Invalid priority: not-a-priority"
            ),
            MalformedFilter(key: "unfinished", value: "not-a-boolean", expectedError: "unfinished must be a boolean"),
            MalformedFilter(key: "search", value: 42, expectedError: "search must be a string"),
            MalformedFilter(key: "displayId", value: "not-an-integer", expectedError: "displayId must be an integer")
        ]

        for milestoneFilter in missingMilestoneFilters {
            for malformedFilter in malformedFilters {
                var arguments = milestoneFilter
                arguments[malformedFilter.key] = malformedFilter.value

                let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
                    tool: "query_tasks",
                    arguments: arguments
                ))

                #expect(try MCPTestHelpers.isError(response))
                #expect(
                    try MCPTestHelpers.errorText(response).contains(malformedFilter.expectedError),
                    "Expected \(malformedFilter.expectedError) before resolving \(milestoneFilter)"
                )
            }
        }
    }
}

#endif
