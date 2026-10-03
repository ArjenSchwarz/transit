#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPTaskQueryFailureTests {
    private enum Failure: Error { case fetch }
    private final class Tasks: TaskFetching {
        var values: [TransitTask] = []
        var shouldFail = false
        var calls = 0
        func fetchAllTasks() throws -> [TransitTask] {
            calls += 1
            if shouldFail { throw Failure.fetch }
            return values
        }
    }
    private final class Comments: CommentFetching {
        var values: [Transit.Comment] = []
        var shouldFail = false
        var calls = 0
        func fetchComments(for taskID: UUID) throws -> [Transit.Comment] {
            calls += 1
            if shouldFail { throw Failure.fetch }
            return values
        }
    }

    @Test func duplicateBatchIDsUseOneTaskAndCommentFetch() async throws {
        let tasks = Tasks()
        let comments = Comments()
        let env = try MCPTestHelpers.makeEnv(taskFetcher: tasks, commentFetcher: comments)
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = TransitTask(name: "Task", type: .bug, project: project, displayID: .permanent(42))
        tasks.values = [task]
        let first = Transit.Comment(content: "First", authorName: "Agent", isAgent: true, task: task)
        let second = Transit.Comment(content: "Second", authorName: "Person", isAgent: false, task: task)
        first.creationDate = Date(timeIntervalSince1970: 0)
        second.creationDate = first.creationDate
        first.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        second.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        comments.values = [second, first]
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: [
                "displayIds": [42, 42, -1], "detailLevel": "summary", "includeComments": true, "limit": 1
            ]
        ))
        let page = try MCPTestHelpers.decodeResult(response)
        let results = try #require(page["results"] as? [[String: Any]])
        let data = try #require(results[0]["task"] as? [String: Any])
        #expect(data["description"] == nil)
        #expect(data["metadata"] == nil)
        let returnedComments = try #require(data["comments"] as? [[String: Any]])
        #expect(returnedComments.map { $0["content"] as? String } == ["First", "Second"])
        #expect(tasks.calls == 1)
        #expect(comments.calls == 1)
        let cursor = try #require(page["nextCursor"] as? String)
        task.name = "Edited"
        first.content = "Edited comment"
        let newComment = Transit.Comment(content: "New comment", authorName: "Agent", isAgent: true, task: task)
        comments.values = [first, newComment]
        comments.shouldFail = true
        tasks.shouldFail = true
        let next = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: ["cursor": cursor]
        ))
        #expect(try !MCPTestHelpers.isError(next))
        let nextResults = try MCPTestHelpers.decodeQueryResults(next)
        let frozenTask = try #require(nextResults[0]["task"] as? [String: Any])
        #expect(frozenTask["name"] as? String == "Task")
        let frozenComments = try #require(frozenTask["comments"] as? [[String: Any]])
        #expect(frozenComments.map { $0["content"] as? String } == ["First", "Second"])
        #expect(frozenComments.map { $0["id"] as? String } == [first.id.uuidString, second.id.uuidString])
        #expect(tasks.calls == 1)
        #expect(comments.calls == 1)
    }

    @Test func summaryCommentsOmittedDoNotFetchAndFullFailuresPublishNothing() async throws {
        let tasks = Tasks()
        let comments = Comments()
        let env = try MCPTestHelpers.makeEnv(taskFetcher: tasks, commentFetcher: comments)
        let project = MCPTestHelpers.makeProject(in: env.context)
        tasks.values = (0..<2).map {
            TransitTask(name: "Task \($0)", type: .chore, project: project, displayID: .provisional)
        }
        comments.shouldFail = true
        let noComments = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: ["detailLevel": "summary", "includeComments": false, "limit": 1]
        ))
        #expect(try !MCPTestHelpers.isError(noComments))
        #expect(comments.calls == 0)
        env.handler.clearTaskQuerySnapshots()
        for includeComments in [false, true] {
            let failed = await env.handler.handle(MCPTestHelpers.toolCallRequest(
                tool: "query_tasks",
                arguments: ["detailLevel": "full", "includeComments": includeComments, "limit": 1]
            ))
            let errorPage = try MCPTestHelpers.decodeResult(failed)
            #expect((errorPage["error"] as? [String: String])?["code"] == "QUERY_FAILED")
            #expect(errorPage["results"] == nil)
            #expect(errorPage["nextCursor"] == nil)
            #expect(env.handler.taskQuerySnapshots.retainedBytes == 0)
        }
        #expect(comments.calls == 2)
    }

    @Test func ambiguousBatchIdentityDoesNotLoseOtherOutcomes() async throws {
        let tasks = Tasks()
        let env = try MCPTestHelpers.makeEnv(taskFetcher: tasks)
        let project = MCPTestHelpers.makeProject(in: env.context)
        tasks.values = [
            TransitTask(name: "A", type: .bug, project: project, displayID: .permanent(42)),
            TransitTask(name: "B", type: .bug, project: project, displayID: .permanent(42)),
            TransitTask(name: "C", type: .bug, project: project, displayID: .permanent(43))
        ]
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: [
                "displayIds": [42, 43, 999], "detailLevel": "summary", "includeComments": false, "limit": 100
            ]
        ))
        let results = try MCPTestHelpers.decodeQueryResults(response)
        #expect((results[0]["error"] as? [String: String])?["code"] == "AMBIGUOUS_TASK_ID")
        #expect((results[1]["task"] as? [String: Any])?["name"] as? String == "C")
        #expect((results[2]["error"] as? [String: String])?["code"] == "TASK_NOT_FOUND")
        #expect(tasks.calls == 1)
    }
}
#endif
