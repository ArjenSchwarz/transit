#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPTaskQueryRevisionTests {
    private final class Comments: CommentFetching {
        var source: (any CommentFetching)?
        var calls: [UUID: Int] = [:]
        var shouldFail = false

        func fetchComments(for taskID: UUID) throws -> [Transit.Comment] {
            calls[taskID, default: 0] += 1
            if shouldFail { throw CocoaError(.fileReadUnknown) }
            return try source?.fetchComments(for: taskID) ?? []
        }
    }

    @Test(arguments: ["list", "single", "uuid_batch", "display_batch"], [false, true])
    func fullQueriesReturnCompleteRevision(selector: String, includeComments: Bool) async throws {
        let comments = Comments()
        let env = try MCPTestHelpers.makeEnv(commentFetcher: comments)
        comments.source = env.commentService
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project)
        let comment = try env.commentService.addComment(
            to: task, content: "Discussion", authorName: "A", isAgent: true)
        let expected = try MCPRecordSnapshot.task(task, in: env.context)
        var args: [String: Any] = ["detailLevel": "full", "includeComments": includeComments, "limit": 100]
        switch selector {
        case "single": args["displayId"] = try #require(task.permanentDisplayId)
        case "uuid_batch": args["taskIds"] = [task.id.uuidString, task.id.uuidString]
        case "display_batch":
            let displayID = try #require(task.permanentDisplayId)
            args["displayIds"] = [displayID, displayID]
        default: break
        }
        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "query_tasks", arguments: args))
        let results = try MCPTestHelpers.decodeQueryResults(response)
        let batch = selector.hasSuffix("batch")
        #expect(results.count == (batch ? 2 : 1))
        for result in results {
            let record = batch ? try #require(result["task"] as? [String: Any]) : result
            #expect(record["revision"] as? String == expected.revision)
            #expect(record["description"] is NSNull)
            #expect(record["metadata"] == nil)
            if includeComments {
                let returned = try #require(record["comments"] as? [[String: Any]])
                #expect(returned.count == 1)
                #expect(returned[0]["revision"] as? String == (try MCPRecordSnapshot.comment(comment).revision))
            } else {
                #expect(record["comments"] == nil)
            }
        }
        #expect(comments.calls[task.id] == 1)
    }

    @Test func hiddenCommentEditChangesFreshRevision() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project)
        let comment = try env.commentService.addComment(to: task, content: "Before", authorName: "A", isAgent: true)
        let args: [String: Any] = ["detailLevel": "full", "includeComments": false, "limit": 100]
        let first = try MCPTestHelpers.decodeQueryResults(
            await env.handler.handle(
                MCPTestHelpers.toolCallRequest(tool: "query_tasks", arguments: args)))
        comment.content = "After"
        try env.context.save()
        let second = try MCPTestHelpers.decodeQueryResults(
            await env.handler.handle(
                MCPTestHelpers.toolCallRequest(tool: "query_tasks", arguments: args)))
        #expect(first[0]["comments"] == nil && second[0]["comments"] == nil)
        #expect(first[0]["revision"] as? String != second[0]["revision"] as? String)
        #expect(second[0]["revision"] as? String == (try MCPRecordSnapshot.task(task, in: env.context).revision))
    }

    @Test func frozenRevisionRejectsWriteAfterHiddenCommentEditWithoutRefetch() async throws {
        let comments = Comments()
        let env = try MCPTestHelpers.makeEnv(commentFetcher: comments)
        comments.source = env.commentService
        let project = MCPTestHelpers.makeProject(in: env.context)
        let first = try await env.taskService.createTask(
            name: "First", description: nil, type: .feature, project: project)
        let task = try await env.taskService.createTask(
            name: "Second", description: nil, type: .feature, project: project)
        let comment = try env.commentService.addComment(to: task, content: "Before", authorName: "A", isAgent: true)
        let before = try MCPRecordSnapshot.task(task, in: env.context).revision
        let page = try MCPTestHelpers.decodeResult(
            await env.handler.handle(
                MCPTestHelpers.toolCallRequest(
                    tool: "query_tasks",
                    arguments: [
                        "taskIds": [first.id.uuidString, task.id.uuidString, task.id.uuidString],
                        "detailLevel": "full", "includeComments": false, "limit": 1
                    ])))
        let cursor = try #require(page["nextCursor"] as? String)
        comment.content = "After"
        try env.context.save()
        comments.shouldFail = true
        let continuation = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(
                tool: "query_tasks", arguments: ["cursor": cursor]))
        let result = try #require(try MCPTestHelpers.decodeQueryResults(continuation).first)
        let frozen = try #require(result["task"] as? [String: Any])
        #expect(frozen["revision"] as? String == before)
        #expect(frozen["comments"] == nil)
        let replay = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(
                tool: "query_tasks", arguments: ["cursor": cursor]))
        #expect(try MCPTestHelpers.errorText(continuation) == MCPTestHelpers.errorText(replay))
        #expect(comments.calls == [first.id: 1, task.id: 1])
        let write = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(
                tool: "update_task",
                arguments: [
                    "taskId": task.id.uuidString, "name": "Must not apply",
                    "expectedRevision": before, "idempotencyKey": UUID().uuidString
                ]))
        #expect(try MCPTestHelpers.errorCode(write) == "REVISION_CONFLICT")
        #expect(task.name == "Second" && comment.content == "After")
    }
}
#endif
