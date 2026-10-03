#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1613: MCP must not turn an unreadable comment store
/// into a successful response with missing or empty comment details.
@MainActor @Suite(.serialized)
struct MCPCommentFetchFailureTests {

    private struct CommentFetchFailure: Swift.Error, CustomStringConvertible {
        var description: String { "simulated comment fetch failure" }
    }

    private final class FailingCommentFetcher: CommentFetching {
        private(set) var fetchCallCount = 0

        func fetchComments(for taskID: UUID) throws -> [Transit.Comment] {
            fetchCallCount += 1
            throw CommentFetchFailure()
        }
    }

    @Test func queryDetailedTaskCommentFetchFailureReturnsExactErrorInsteadOfEmptyComments() async throws {
        let failingFetcher = FailingCommentFetcher()
        let env = try MCPTestHelpers.makeEnv(commentFetcher: failingFetcher)
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: ["detailLevel": "summary", "includeComments": true, "limit": 100,
                "displayId": displayId]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(
            try MCPTestHelpers.queryErrorMessage(response)
                == "Failed to fetch comments: simulated comment fetch failure"
        )
    }

    @Test func queryTaskListCommentFetchFailureReturnsExactErrorInsteadOfEmptyComments() async throws {
        let failingFetcher = FailingCommentFetcher()
        let env = try MCPTestHelpers.makeEnv(commentFetcher: failingFetcher)
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: ["detailLevel": "summary", "includeComments": true, "limit": 100]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(
            try MCPTestHelpers.queryErrorMessage(response)
                == "Failed to fetch comments: simulated comment fetch failure"
        )
    }

    @Test func queryTaskWithValidEmptyCommentsReturnsSuccessfulEmptyArray() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: ["detailLevel": "summary", "includeComments": true, "limit": 100,
                "displayId": displayId]
        ))

        #expect(try !MCPTestHelpers.isError(response))
        let result = try #require(MCPTestHelpers.decodeQueryResults(response).first)
        #expect((result["comments"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test func updateStatusWithCommentDoesNotFetchResponseDetailsAfterPersisting() async throws {
        let failingFetcher = FailingCommentFetcher()
        let env = try MCPTestHelpers.makeEnv(commentFetcher: failingFetcher)
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(try MCPTestHelpers.protectedToolCallRequest(
            in: env.context, tool: "update_task_status",
            arguments: [
                "displayId": displayId, "status": "planning",
                "comment": "Persisted exactly once", "authorName": "TestBot"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect((result["record"] as? [String: Any])?["status"] as? String == "planning")
        #expect((result["comment"] as? [String: Any])?["content"] as? String == "Persisted exactly once")
        #expect(failingFetcher.fetchCallCount == 0)

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.count == 1)
        #expect(comments.first?.content == "Persisted exactly once")
    }
}

#endif
