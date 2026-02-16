import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct AddCommentIntentTests {
    private struct TestServices {
        let task: TaskService
        let comment: CommentService
        let context: ModelContext
    }

    private func makeServices() throws -> TestServices {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return TestServices(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            comment: CommentService(modelContext: context),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test Project", description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    private func makeTask(svc: TestServices) async throws -> TransitTask {
        let project = makeProject(in: svc.context)
        return try await svc.task.createTask(
            name: "Test Task", description: nil, type: .feature, project: project
        )
    }

    private func intentServices(_ svc: TestServices) -> AddCommentIntent.Services {
        AddCommentIntent.Services(taskService: svc.task, commentService: svc.comment)
    }

    // MARK: - Valid Input

    @Test func performValidInputCreatesComment() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        try AddCommentIntent.execute(
            taskIdentifier: "\(task.permanentDisplayId!)", // swiftlint:disable:this force_unwrapping
            commentText: "Test comment",
            authorName: "TestBot",
            isAgent: true,
            services: intentServices(svc)
        )

        let comments = try svc.comment.fetchComments(for: task.id)
        #expect(comments.count == 1)
        #expect(comments[0].content == "Test comment")
        #expect(comments[0].authorName == "TestBot")
    }

    // MARK: - Task Not Found

    @Test func performTaskNotFoundThrowsError() async throws {
        let svc = try makeServices()

        #expect(throws: VisualIntentError.self) {
            try AddCommentIntent.execute(
                taskIdentifier: "999",
                commentText: "Test comment",
                authorName: "TestBot",
                isAgent: true,
                services: intentServices(svc)
            )
        }
    }

    // MARK: - Empty Content

    @Test func performEmptyContentThrowsError() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        #expect(throws: VisualIntentError.self) {
            try AddCommentIntent.execute(
                taskIdentifier: "\(task.permanentDisplayId!)", // swiftlint:disable:this force_unwrapping
                commentText: "   ",
                authorName: "TestBot",
                isAgent: true,
                services: intentServices(svc)
            )
        }
    }

    // MARK: - Empty Author Name

    @Test func performEmptyAuthorNameThrowsError() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        #expect(throws: VisualIntentError.self) {
            try AddCommentIntent.execute(
                taskIdentifier: "\(task.permanentDisplayId!)", // swiftlint:disable:this force_unwrapping
                commentText: "Valid comment",
                authorName: "   ",
                isAgent: true,
                services: intentServices(svc)
            )
        }
    }

    // MARK: - isAgent Defaults

    @Test func performIsAgentTrue() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        try AddCommentIntent.execute(
            taskIdentifier: "\(task.permanentDisplayId!)", // swiftlint:disable:this force_unwrapping
            commentText: "Agent comment",
            authorName: "TestBot",
            isAgent: true,
            services: intentServices(svc)
        )

        let comments = try svc.comment.fetchComments(for: task.id)
        #expect(comments[0].isAgent == true)
    }

    @Test func performIsAgentFalseWhenToggled() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        try AddCommentIntent.execute(
            taskIdentifier: "\(task.permanentDisplayId!)", // swiftlint:disable:this force_unwrapping
            commentText: "User comment",
            authorName: "Human",
            isAgent: false,
            services: intentServices(svc)
        )

        let comments = try svc.comment.fetchComments(for: task.id)
        #expect(comments[0].isAgent == false)
    }

    // MARK: - Identifier Formats

    @Test func performAcceptsDisplayIdString() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        try AddCommentIntent.execute(
            taskIdentifier: "1",
            commentText: "Comment via display ID",
            authorName: "TestBot",
            isAgent: true,
            services: intentServices(svc)
        )

        let comments = try svc.comment.fetchComments(for: task.id)
        #expect(comments.count == 1)
    }

    @Test func performAcceptsUUIDString() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        try AddCommentIntent.execute(
            taskIdentifier: task.id.uuidString,
            commentText: "Comment via UUID",
            authorName: "TestBot",
            isAgent: true,
            services: intentServices(svc)
        )

        let comments = try svc.comment.fetchComments(for: task.id)
        #expect(comments.count == 1)
    }
}
