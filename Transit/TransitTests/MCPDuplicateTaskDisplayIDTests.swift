#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-1837 regression: MCP task tools resolved a `displayId` through
/// `TaskService.resolveTask` and swallowed `.duplicateDisplayID` in a catch-all
/// branch, so duplicate-identifier corruption was reported as "provide either
/// displayId or taskId". Duplicates must be reported as duplicates, matching the
/// wording the milestone tools already use.
@MainActor @Suite(.serialized)
struct MCPDuplicateTaskDisplayIDTests {

    /// Inserts two tasks sharing `displayId`, simulating a CloudKit sync conflict.
    @discardableResult
    private func makeDuplicatePair(
        in context: ModelContext, displayId: Int
    ) -> (TransitTask, TransitTask) {
        let project = MCPTestHelpers.makeProject(in: context)
        let first = TransitTask(
            name: "First", type: .feature, project: project, displayID: .permanent(displayId)
        )
        let second = TransitTask(
            name: "Second", type: .feature, project: project, displayID: .permanent(displayId)
        )
        StatusEngine.initializeNewTask(first)
        StatusEngine.initializeNewTask(second)
        context.insert(first)
        context.insert(second)
        return (first, second)
    }

    private func expectDuplicateError(
        _ response: JSONRPCResponse?, displayId: Int
    ) throws {
        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.lowercased().contains("duplicate"))
        #expect(text.contains("\(displayId)"))
    }

    // MARK: - update_task_status

    @Test func updateStatusReportsDuplicateDisplayID() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let (first, second) = makeDuplicatePair(in: env.context, displayId: 42)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 42, "status": "in-progress"]
        ))

        try expectDuplicateError(response, displayId: 42)
        #expect(first.statusRawValue == "idea")
        #expect(second.statusRawValue == "idea")
    }

    @Test func updateStatusStillReportsMissingTaskGenerically() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 999, "status": "in-progress"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(!text.lowercased().contains("duplicate"))
    }

    // MARK: - update_task

    @Test func updateTaskReportsDuplicateDisplayID() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let (first, second) = makeDuplicatePair(in: env.context, displayId: 42)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": 42, "name": "Renamed"]
        ))

        try expectDuplicateError(response, displayId: 42)
        #expect(first.name == "First")
        #expect(second.name == "Second")
    }

    // MARK: - add_comment

    @Test func addCommentReportsDuplicateDisplayID() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let (first, second) = makeDuplicatePair(in: env.context, displayId: 42)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: ["displayId": 42, "content": "Hello", "authorName": "TestBot"]
        ))

        try expectDuplicateError(response, displayId: 42)
        #expect(try env.commentService.fetchComments(for: first.id).isEmpty)
        #expect(try env.commentService.fetchComments(for: second.id).isEmpty)
    }

    // MARK: - query_tasks

    @Test func queryTasksReportsDuplicateDisplayID() async throws {
        let env = try MCPTestHelpers.makeEnv()
        makeDuplicatePair(in: env.context, displayId: 42)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": 42]
        ))

        try expectDuplicateError(response, displayId: 42)
    }
}
#endif
