#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1544: Reject non-string `status` on update_task_status before any mutation.
@MainActor @Suite(.serialized)
struct MCPUpdateStatusValidationTests {

    /// Creates a task with a known permanent display ID for testing.
    private func makeTask(
        in context: ModelContext,
        project: Project,
        displayId: Int
    ) -> TransitTask {
        let task = TransitTask(name: "Test Task", type: .feature, project: project, displayID: .permanent(displayId))
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        return task
    }

    @Test func numericStatusReturnsErrorAndDoesNotMutate() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = makeTask(in: env.context, project: project, displayId: 1)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 1, "status": 123]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("status must be a string"))

        // The task must not have been mutated.
        #expect(task.statusRawValue == "idea")
    }

    @Test func booleanStatusReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        makeTask(in: env.context, project: project, displayId: 1)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 1, "status": true]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("status must be a string"))
    }

    @Test func arrayStatusReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        makeTask(in: env.context, project: project, displayId: 1)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 1, "status": ["done"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("status must be a string"))
    }

    @Test func nullStatusReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        makeTask(in: env.context, project: project, displayId: 1)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 1, "status": NSNull()]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("status must be a string"))
    }

    /// A truly missing status keeps its original "Missing required argument" message.
    @Test func missingStatusStillReportsMissingArgument() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        makeTask(in: env.context, project: project, displayId: 1)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 1]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("Missing required argument: status"))
    }
}

#endif
