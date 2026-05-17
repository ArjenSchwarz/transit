#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1205: Reject non-string comment / authorName on update_task_status.
@MainActor @Suite(.serialized)
struct MCPCommentTypeValidationTests {

    // update_task_status: numeric comment must error and must NOT change status.
    @Test func updateStatusNumericCommentReturnsErrorAndDoesNotChangeStatus() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)
        let originalStatus = task.statusRawValue

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "displayId": displayId,
                "status": "planning",
                "comment": 123,
                "authorName": "Bot"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("comment"))

        // Status must not have been changed
        let refreshed = try env.taskService.findByDisplayID(displayId)
        #expect(refreshed.statusRawValue == originalStatus)

        // No comment must have been created
        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    @Test func updateStatusBooleanCommentReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)
        let originalStatus = task.statusRawValue

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "displayId": displayId,
                "status": "planning",
                "comment": true,
                "authorName": "Bot"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("comment"))

        let refreshed = try env.taskService.findByDisplayID(displayId)
        #expect(refreshed.statusRawValue == originalStatus)
    }

    @Test func updateStatusArrayCommentReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)
        let originalStatus = task.statusRawValue

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "displayId": displayId,
                "status": "planning",
                "comment": ["nested"],
                "authorName": "Bot"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("comment"))

        let refreshed = try env.taskService.findByDisplayID(displayId)
        #expect(refreshed.statusRawValue == originalStatus)
    }

    @Test func updateStatusNumericAuthorNameReturnsErrorAndDoesNotChangeStatus() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)
        let originalStatus = task.statusRawValue

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "displayId": displayId,
                "status": "planning",
                "comment": "Note",
                "authorName": 42
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("authorName"))

        let refreshed = try env.taskService.findByDisplayID(displayId)
        #expect(refreshed.statusRawValue == originalStatus)

        // No comment must have been created
        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    // Sanity: NSNull (decoded JSON null) is also a non-string present value.
    @Test func updateStatusNullCommentReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)
        let originalStatus = task.statusRawValue

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "displayId": displayId,
                "status": "planning",
                "comment": NSNull(),
                "authorName": "Bot"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("comment"))

        let refreshed = try env.taskService.findByDisplayID(displayId)
        #expect(refreshed.statusRawValue == originalStatus)
    }
}

#endif
