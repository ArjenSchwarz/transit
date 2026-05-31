#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// Bug T-1404: the `type` filter was validated with the generic validateEnumFilter,
// which accepts both a single string and [String]. The query_tasks schema declares
// `type` as a single string enum, and handleQueryTasks reads it back with
// `args["type"] as? String`. So `{"type": ["bug"]}` passed validation but then became
// nil, silently returning all task types instead of filtering. The fixed behaviour is
// to reject array `type` inputs (validateEnumFilter is called with allowArray: false).
@MainActor @Suite(.serialized)
struct MCPQueryTasksTypeArrayValidationTests {

    @Test func queryTasksTypeArraySingleValueReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["type": ["bug"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("type"))
        #expect(text.contains("expected a string"))
    }

    @Test func queryTasksTypeArrayMultipleValuesReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["type": ["bug", "feature"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("type"))
        #expect(text.contains("expected a string"))
    }

    // Critical regression check — without the fix, an array type filter is dropped to nil
    // and the query returns tasks of every type instead of an error.
    @Test func queryTasksTypeArrayDoesNotReturnUnfilteredResults() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Bug task", description: nil, type: .bug, project: project
        )
        _ = try await env.taskService.createTask(
            name: "Feature task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["type": ["bug"]]
        ))

        // Bug behaviour: array is dropped to nil and both tasks are returned.
        // Fixed behaviour: an isError response, not an unfiltered list.
        #expect(try MCPTestHelpers.isError(response))
    }
}

#endif
