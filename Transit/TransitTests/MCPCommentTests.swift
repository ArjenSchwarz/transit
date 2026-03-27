#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPCommentTests {

    // MARK: - add_comment

    @Test func addCommentValidInputCreatesComment() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": 1,
                "content": "Test comment",
                "authorName": "TestBot"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["id"] is String)
        #expect(result["authorName"] as? String == "TestBot")
        #expect(result["content"] as? String == "Test comment")
        #expect(result["creationDate"] is String)

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.count == 1)
        #expect(comments[0].isAgent == true)
    }

    @Test func addCommentMissingContentReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: ["displayId": 1, "authorName": "Bot"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func addCommentMissingAuthorNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: ["displayId": 1, "content": "Hello"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func addCommentTaskNotFoundReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: ["displayId": 999, "content": "Hello", "authorName": "Bot"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    // MARK: - update_task_status with comment

    @Test func updateStatusWithCommentCreatesComment() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "displayId": 1,
                "status": "planning",
                "comment": "Moving to planning",
                "authorName": "TestBot"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["status"] as? String == "planning")

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.count == 1)
        #expect(comments[0].content == "Moving to planning")
        #expect(comments[0].authorName == "TestBot")
        #expect(comments[0].isAgent == true)

        let commentDict = try #require(result["comment"] as? [String: Any])
        #expect(commentDict["content"] as? String == "Moving to planning")
        #expect(commentDict["authorName"] as? String == "TestBot")
    }

    @Test func updateStatusWithCommentRequiresAuthorName() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "displayId": 1,
                "status": "planning",
                "comment": "Moving to planning"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func updateStatusWithoutCommentBehavesAsExisting() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: ["displayId": 1, "status": "planning"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["status"] as? String == "planning")
        #expect(result["comment"] == nil)

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    @Test func updateStatusWithWhitespaceOnlyCommentIgnoresComment() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "displayId": 1,
                "status": "planning",
                "comment": "   ",
                "authorName": "Bot"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["status"] as? String == "planning")
        #expect(result["comment"] == nil)

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    // MARK: - Literal backslash-n preservation (T-576)

    @Test func addCommentPreservesLiteralBackslashN() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        // Swift string "C:\\new\\notes" is runtime C:\new\notes (literal backslash-n).
        // This simulates a JSON-decoded string from: "C:\\new\\notes" in JSON,
        // where the user intended to keep the literal backslash-n (e.g., Windows path).
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": 1,
                "content": "Path: C:\\new\\notes",
                "authorName": "Bot"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["content"] as? String == "Path: C:\\new\\notes")

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.count == 1)
        #expect(comments[0].content == "Path: C:\\new\\notes")
    }

    @Test func updateStatusCommentPreservesLiteralBackslashN() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        // The comment contains a literal backslash-n that should NOT be turned into a newline.
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task_status",
            arguments: [
                "displayId": 1,
                "status": "planning",
                "comment": "See C:\\new folder",
                "authorName": "Bot"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let commentDict = try #require(result["comment"] as? [String: Any])
        #expect(commentDict["content"] as? String == "See C:\\new folder")

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments[0].content == "See C:\\new folder")
    }

    @Test func addCommentPreservesRealNewlines() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": 1,
                "content": "Line one\nLine two",
                "authorName": "Bot"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["content"] as? String == "Line one\nLine two")
    }

    // MARK: - query_tasks with comments

    @Test func queryTasksIncludesCommentsArray() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        try env.commentService.addComment(
            to: task, content: "First", authorName: "Bot", isAgent: true
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let first = try #require(results.first)
        let comments = try #require(first["comments"] as? [[String: Any]])
        #expect(comments.count == 1)
        #expect(comments[0]["content"] as? String == "First")
        #expect(comments[0]["authorName"] as? String == "Bot")
        #expect(comments[0]["isAgent"] as? Bool == true)
    }

    @Test func queryTasksCommentsOrderedChronologically() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        try env.commentService.addComment(
            to: task, content: "First", authorName: "Bot", isAgent: true
        )
        try await Task.sleep(for: .milliseconds(10))
        try env.commentService.addComment(
            to: task, content: "Second", authorName: "Bot", isAgent: true
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let first = try #require(results.first)
        let comments = try #require(first["comments"] as? [[String: Any]])
        #expect(comments.count == 2)
        #expect(comments[0]["content"] as? String == "First")
        #expect(comments[1]["content"] as? String == "Second")
    }

    @Test func queryTasksNoCommentsEmptyArray() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let first = try #require(results.first)
        let comments = try #require(first["comments"] as? [[String: Any]])
        #expect(comments.isEmpty)
    }
}

#endif
