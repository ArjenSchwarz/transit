#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-808: Regression tests for MCP task tool handlers verifying that
/// malformed task identifiers (`displayId` and `taskId`) are rejected with a
/// field-specific message instead of silently falling through to the other
/// key or to a generic task-not-found error.
@MainActor @Suite(.serialized)
struct MCPTaskIdentifierValidationTests {

    @Test func mcpUpdateStatusMalformedDisplayIdDoesNotFallBackToTaskId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "displayId": "abc",
                "taskId": task.id.uuidString,
                "status": "in-progress"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))

        // Status must NOT have been changed via taskId fallback.
        // First task in a fresh in-memory context gets provisional displayId 1.
        let refetched = try env.taskService.findByDisplayID(1)
        #expect(refetched.statusRawValue == "idea")
    }

    @Test func mcpUpdateStatusNonStringTaskIdReturnsFieldSpecificError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "taskId": 123,
                "status": "in-progress"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("taskId"))
    }

    @Test func mcpUpdateTaskMalformedDisplayIdDoesNotFallBackToTaskId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        _ = try await env.milestoneService.createMilestone(
            name: "M1", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: [
                "displayId": "abc",
                "taskId": task.id.uuidString,
                "milestoneDisplayId": 1
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))

        // Milestone must NOT have been assigned via taskId fallback.
        let refetched = try env.taskService.findByDisplayID(1)
        #expect(refetched.milestone == nil)
    }

    @Test func mcpAddCommentMalformedDisplayIdDoesNotFallBackToTaskId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": "abc",
                "taskId": task.id.uuidString,
                "content": "Hello",
                "authorName": "Tester"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("displayId must be an integer"))

        // Comment must NOT have been added via taskId fallback.
        let refetched = try env.taskService.findByDisplayID(1)
        #expect((refetched.comments ?? []).isEmpty)
    }

    @Test func mcpAddCommentNonStringTaskIdReturnsFieldSpecificError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "taskId": 123,
                "content": "Hello",
                "authorName": "Tester"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("taskId"))
    }
}

#endif
