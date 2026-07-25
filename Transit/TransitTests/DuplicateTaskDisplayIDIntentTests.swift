import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-1837 regression: when more than one task carries the same
/// `permanentDisplayId` (possible under CloudKit, which cannot enforce unique
/// constraints), `TaskService.findByDisplayID` throws `.duplicateDisplayID`.
/// Every App Intent mutation surface used to collapse that into
/// `TASK_NOT_FOUND`, so an operator could not tell missing data apart from
/// store corruption that needs display-ID maintenance. The duplicate must
/// surface as `INTERNAL_ERROR`, matching the milestone paths and the
/// `QueryTasksIntent` fix from T-1097.
@MainActor @Suite(.serialized)
struct DuplicateTaskDisplayIDIntentTests {

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let milestone: MilestoneService
        let comment: CommentService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let taskAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: taskAllocator),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator),
            comment: CommentService(modelContext: context),
            context: context
        )
    }

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(
            name: "Alpha", description: "A test project", gitRepo: nil, colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }

    /// Inserts two tasks sharing `displayId`, simulating a CloudKit sync conflict.
    @discardableResult
    private func makeDuplicatePair(
        in context: ModelContext, displayId: Int
    ) -> (TransitTask, TransitTask) {
        let project = makeProject(in: context)
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

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func expectDuplicateError(_ json: String, displayId: Int) throws {
        let parsed = try parseJSON(json)
        #expect(parsed["error"] as? String == "INTERNAL_ERROR")
        let hint = try #require(parsed["hint"] as? String)
        #expect(hint.lowercased().contains("duplicate"))
        #expect(hint.contains("\(displayId)"))
    }

    // MARK: - Shared resolver

    @Test func resolveTaskReportsDuplicateDisplayIDAsInternalError() throws {
        let svc = try makeServices()
        makeDuplicatePair(in: svc.context, displayId: 42)

        let result = IntentHelpers.resolveTask(from: ["displayId": 42], taskService: svc.task)

        guard case .failure(let error) = result else {
            Issue.record("Expected duplicate display ID to fail resolution")
            return
        }
        #expect(error.code == "INTERNAL_ERROR")
        #expect(error.hint.lowercased().contains("duplicate"))
    }

    @Test func resolveTaskStillReportsMissingTaskAsNotFound() throws {
        let svc = try makeServices()

        let result = IntentHelpers.resolveTask(from: ["displayId": 999], taskService: svc.task)

        guard case .failure(let error) = result else {
            Issue.record("Expected missing task to fail resolution")
            return
        }
        #expect(error.code == "TASK_NOT_FOUND")
    }

    // MARK: - UpdateStatusIntent

    @Test func updateStatusIntentReportsDuplicateDisplayID() throws {
        let svc = try makeServices()
        let (first, second) = makeDuplicatePair(in: svc.context, displayId: 42)

        let result = UpdateStatusIntent.execute(
            input: #"{"displayId":42,"status":"in-progress"}"#,
            taskService: svc.task
        )

        try expectDuplicateError(result, displayId: 42)
        // Neither ambiguous task may be mutated.
        #expect(first.statusRawValue == "idea")
        #expect(second.statusRawValue == "idea")
    }

    @Test func updateStatusIntentStillReportsMissingTaskAsNotFound() throws {
        let svc = try makeServices()

        let result = UpdateStatusIntent.execute(
            input: #"{"displayId":999,"status":"in-progress"}"#,
            taskService: svc.task
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "TASK_NOT_FOUND")
    }

    // MARK: - UpdateTaskIntent

    @Test func updateTaskIntentReportsDuplicateDisplayID() throws {
        let svc = try makeServices()
        let (first, second) = makeDuplicatePair(in: svc.context, displayId: 42)

        let result = UpdateTaskIntent.execute(
            input: #"{"displayId":42,"name":"Renamed"}"#,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        try expectDuplicateError(result, displayId: 42)
        #expect(first.name == "First")
        #expect(second.name == "Second")
    }

    // MARK: - AddCommentIntent

    @Test func addCommentIntentReportsDuplicateDisplayID() throws {
        let svc = try makeServices()
        let (first, second) = makeDuplicatePair(in: svc.context, displayId: 42)

        var thrown: VisualIntentError?
        #expect(throws: VisualIntentError.self) {
            do {
                try AddCommentIntent.execute(
                    taskIdentifier: "42",
                    commentText: "Hello",
                    authorName: "TestBot",
                    isAgent: true,
                    services: AddCommentIntent.Services(
                        taskService: svc.task, commentService: svc.comment
                    )
                )
            } catch let error as VisualIntentError {
                thrown = error
                throw error
            }
        }

        let error = try #require(thrown)
        #expect(error.code == "INTERNAL_ERROR")
        #expect(error.errorDescription?.lowercased().contains("duplicate") == true)
        #expect(try svc.comment.fetchComments(for: first.id).isEmpty)
        #expect(try svc.comment.fetchComments(for: second.id).isEmpty)
    }

    @Test func addCommentIntentStillReportsMissingTaskAsNotFound() throws {
        let svc = try makeServices()

        var thrown: VisualIntentError?
        #expect(throws: VisualIntentError.self) {
            do {
                try AddCommentIntent.execute(
                    taskIdentifier: "999",
                    commentText: "Hello",
                    authorName: "TestBot",
                    isAgent: true,
                    services: AddCommentIntent.Services(
                        taskService: svc.task, commentService: svc.comment
                    )
                )
            } catch let error as VisualIntentError {
                thrown = error
                throw error
            }
        }

        #expect(try #require(thrown).code == "TASK_NOT_FOUND")
    }
}
