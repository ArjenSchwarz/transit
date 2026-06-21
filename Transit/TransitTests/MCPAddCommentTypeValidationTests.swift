#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

// T-1579: Reject non-string content / authorName on add_comment.
// A present-but-non-string value must surface a field-specific type error
// ("content must be a string" / "authorName must be a string") rather than
// being collapsed into the generic "Missing required argument" message, and
// no comment must be created.
@MainActor @Suite(.serialized)
struct MCPAddCommentTypeValidationTests {

    // MARK: - content

    @Test func addCommentNumericContentReturnsTypeErrorAndCreatesNoComment() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": displayId,
                "content": 123,
                "authorName": "Bot"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("content"))
        // Must not be misreported as missing.
        #expect(!text.contains("Missing required argument"))

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    @Test func addCommentBooleanContentReturnsTypeError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": displayId,
                "content": true,
                "authorName": "Bot"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("content"))

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    @Test func addCommentArrayContentReturnsTypeError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": displayId,
                "content": ["nested"],
                "authorName": "Bot"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("content"))

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    // Sanity: NSNull (decoded JSON null) is also a non-string present value.
    @Test func addCommentNullContentReturnsTypeError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": displayId,
                "content": NSNull(),
                "authorName": "Bot"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("content"))

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    // MARK: - authorName

    @Test func addCommentNumericAuthorNameReturnsTypeErrorAndCreatesNoComment() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": displayId,
                "content": "Note",
                "authorName": 42
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("authorName"))
        // Must not be misreported as missing.
        #expect(!text.contains("Missing required argument"))

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    @Test func addCommentBooleanAuthorNameReturnsTypeError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": displayId,
                "content": "Note",
                "authorName": false
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("authorName"))

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    @Test func addCommentNullAuthorNameReturnsTypeError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "add_comment",
            arguments: [
                "displayId": displayId,
                "content": "Note",
                "authorName": NSNull()
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("authorName"))

        let comments = try env.commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }
}

#endif
