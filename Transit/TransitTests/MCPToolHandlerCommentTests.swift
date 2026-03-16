#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPToolHandlerCommentTests {

    @Test func updateStatusNoOpWithCommentReturnsNewComment() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)
        try env.taskService.updateStatus(task: task, to: .planning)

        // Add a pre-existing comment so we can detect stale returns
        try env.commentService.addComment(
            to: task, content: "Old comment", authorName: "OldAgent", isAgent: true
        )

        // No-op status change WITH a new comment
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "displayId": displayId, "status": "planning",
                "comment": "Fresh note", "authorName": "NewAgent"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["previousStatus"] as? String == "planning")
        #expect(result["status"] as? String == "planning")

        // The returned comment must be the NEW one, not the stale old one
        let comment = try #require(result["comment"] as? [String: Any])
        #expect(comment["content"] as? String == "Fresh note")
        #expect(comment["authorName"] as? String == "NewAgent")
    }

    @Test func updateStatusNoOpWithoutCommentOmitsCommentDetails() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)
        try env.taskService.updateStatus(task: task, to: .planning)

        // Add a pre-existing comment
        try env.commentService.addComment(
            to: task, content: "Old comment", authorName: "Agent", isAgent: true
        )

        // No-op status change WITHOUT a comment — must not return stale comment
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": displayId, "status": "planning"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["comment"] == nil, "No-op without comment should not return stale comment details")
    }
}

#endif
