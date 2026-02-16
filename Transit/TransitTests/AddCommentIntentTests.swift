import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct AddCommentIntentTests {
    private struct Services {
        let task: TaskService
        let comment: CommentService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
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

    private func makeTask(svc: Services) async throws -> TransitTask {
        let project = makeProject(in: svc.context)
        return try await svc.task.createTask(
            name: "Test Task", description: nil, type: .feature, project: project
        )
    }

    // MARK: - Valid Input

    @Test func performValidInputCreatesComment() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        var intent = AddCommentIntent()
        intent.taskIdentifier = "\(task.permanentDisplayId!)" // swiftlint:disable:this force_unwrapping
        intent.commentText = "Test comment"
        intent.authorName = "TestBot"
        intent.isAgent = true
        intent.$taskService.wrappedValue = svc.task
        intent.$commentService.wrappedValue = svc.comment

        _ = try await intent.perform()

        let comments = try svc.comment.fetchComments(for: task.id)
        #expect(comments.count == 1)
        #expect(comments[0].content == "Test comment")
        #expect(comments[0].authorName == "TestBot")
    }

    // MARK: - Task Not Found

    @Test func performTaskNotFoundThrowsError() async throws {
        let svc = try makeServices()

        var intent = AddCommentIntent()
        intent.taskIdentifier = "999"
        intent.commentText = "Test comment"
        intent.authorName = "TestBot"
        intent.isAgent = true
        intent.$taskService.wrappedValue = svc.task
        intent.$commentService.wrappedValue = svc.comment

        await #expect(throws: VisualIntentError.self) {
            _ = try await intent.perform()
        }
    }

    // MARK: - Empty Content

    @Test func performEmptyContentThrowsError() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        var intent = AddCommentIntent()
        intent.taskIdentifier = "\(task.permanentDisplayId!)" // swiftlint:disable:this force_unwrapping
        intent.commentText = "   "
        intent.authorName = "TestBot"
        intent.isAgent = true
        intent.$taskService.wrappedValue = svc.task
        intent.$commentService.wrappedValue = svc.comment

        await #expect(throws: VisualIntentError.self) {
            _ = try await intent.perform()
        }
    }

    // MARK: - Empty Author Name

    @Test func performEmptyAuthorNameThrowsError() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        var intent = AddCommentIntent()
        intent.taskIdentifier = "\(task.permanentDisplayId!)" // swiftlint:disable:this force_unwrapping
        intent.commentText = "Valid comment"
        intent.authorName = "   "
        intent.isAgent = true
        intent.$taskService.wrappedValue = svc.task
        intent.$commentService.wrappedValue = svc.comment

        await #expect(throws: VisualIntentError.self) {
            _ = try await intent.perform()
        }
    }

    // MARK: - isAgent Defaults

    @Test func performDefaultsIsAgentTrue() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        var intent = AddCommentIntent()
        intent.taskIdentifier = "\(task.permanentDisplayId!)" // swiftlint:disable:this force_unwrapping
        intent.commentText = "Agent comment"
        intent.authorName = "TestBot"
        // isAgent defaults to true per @Parameter(default: true)
        intent.$taskService.wrappedValue = svc.task
        intent.$commentService.wrappedValue = svc.comment

        _ = try await intent.perform()

        let comments = try svc.comment.fetchComments(for: task.id)
        #expect(comments[0].isAgent == true)
    }

    @Test func performIsAgentFalseWhenToggled() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        var intent = AddCommentIntent()
        intent.taskIdentifier = "\(task.permanentDisplayId!)" // swiftlint:disable:this force_unwrapping
        intent.commentText = "User comment"
        intent.authorName = "Human"
        intent.isAgent = false
        intent.$taskService.wrappedValue = svc.task
        intent.$commentService.wrappedValue = svc.comment

        _ = try await intent.perform()

        let comments = try svc.comment.fetchComments(for: task.id)
        #expect(comments[0].isAgent == false)
    }

    // MARK: - Identifier Formats

    @Test func performAcceptsDisplayIdString() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        var intent = AddCommentIntent()
        intent.taskIdentifier = "1" // display ID
        intent.commentText = "Comment via display ID"
        intent.authorName = "TestBot"
        intent.isAgent = true
        intent.$taskService.wrappedValue = svc.task
        intent.$commentService.wrappedValue = svc.comment

        _ = try await intent.perform()

        let comments = try svc.comment.fetchComments(for: task.id)
        #expect(comments.count == 1)
    }

    @Test func performAcceptsUUIDString() async throws {
        let svc = try makeServices()
        let task = try await makeTask(svc: svc)

        var intent = AddCommentIntent()
        intent.taskIdentifier = task.id.uuidString
        intent.commentText = "Comment via UUID"
        intent.authorName = "TestBot"
        intent.isAgent = true
        intent.$taskService.wrappedValue = svc.task
        intent.$commentService.wrappedValue = svc.comment

        _ = try await intent.perform()

        let comments = try svc.comment.fetchComments(for: task.id)
        #expect(comments.count == 1)
    }
}
