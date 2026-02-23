import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct CommentServiceTests {

    // MARK: - Helpers

    private func makeService() throws -> (CommentService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let service = CommentService(modelContext: context)
        return (service, context)
    }

    private func makeTask(in context: ModelContext) -> TransitTask {
        let project = Project(name: "Test", description: "Test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(1))
        context.insert(task)
        return task
    }

    // MARK: - addComment

    @Test func addComment_createsWithCorrectFields() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        let comment = try service.addComment(
            to: task, content: "Hello", authorName: "Alice", isAgent: false
        )

        #expect(comment.content == "Hello")
        #expect(comment.authorName == "Alice")
        #expect(comment.isAgent == false)
        #expect(comment.task?.id == task.id)
        #expect(comment.creationDate <= Date.now)
    }

    @Test func addComment_emptyContent_throws() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        #expect(throws: CommentService.Error.emptyContent) {
            try service.addComment(to: task, content: "", authorName: "Alice", isAgent: false)
        }
    }

    @Test func addComment_whitespaceOnlyContent_throws() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        #expect(throws: CommentService.Error.emptyContent) {
            try service.addComment(to: task, content: "   \n  ", authorName: "Alice", isAgent: false)
        }
    }

    @Test func addComment_emptyAuthorName_throws() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        #expect(throws: CommentService.Error.emptyAuthorName) {
            try service.addComment(to: task, content: "Hello", authorName: "", isAgent: false)
        }
    }

    @Test func addComment_trimmedContent_isSaved() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        let comment = try service.addComment(
            to: task, content: "  trimmed  ", authorName: "  Bob  ", isAgent: false
        )

        #expect(comment.content == "trimmed")
        #expect(comment.authorName == "Bob")
    }

    @Test func addComment_isAgent_preservedOnCreation() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        let agentComment = try service.addComment(
            to: task, content: "Agent note", authorName: "claude-code", isAgent: true
        )
        let userComment = try service.addComment(
            to: task, content: "User note", authorName: "Alice", isAgent: false
        )

        #expect(agentComment.isAgent == true)
        #expect(userComment.isAgent == false)
    }

    @Test func addComment_saveFalse_doesNotPersistUntilExplicitSave() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        _ = try service.addComment(
            to: task, content: "Deferred", authorName: "Alice", isAgent: false, save: false
        )

        // Roll back unsaved changes
        context.rollback()

        // After rollback, the comment should not exist
        let comments = try service.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    // MARK: - deleteComment

    @Test func deleteComment_removesFromStore() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        let comment = try service.addComment(
            to: task, content: "To delete", authorName: "Alice", isAgent: false
        )

        try service.deleteComment(comment)

        let comments = try service.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    // MARK: - fetchComments

    @Test func fetchComments_orderedByCreationDate() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        let older = Comment(content: "First", authorName: "Alice", isAgent: false, task: task)
        older.creationDate = Date(timeIntervalSince1970: 1000)
        context.insert(older)

        let newer = Comment(content: "Second", authorName: "Bob", isAgent: false, task: task)
        newer.creationDate = Date(timeIntervalSince1970: 2000)
        context.insert(newer)

        try context.save()

        let comments = try service.fetchComments(for: task.id)
        #expect(comments.count == 2)
        #expect(comments[0].content == "First")
        #expect(comments[1].content == "Second")
    }

    @Test func fetchComments_emptyForTaskWithNoComments() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        let comments = try service.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }

    // MARK: - commentCount

    @Test func commentCount_returnsCorrectCount() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        try service.addComment(to: task, content: "One", authorName: "Alice", isAgent: false)
        try service.addComment(to: task, content: "Two", authorName: "Alice", isAgent: false)
        try service.addComment(to: task, content: "Three", authorName: "Alice", isAgent: false)

        let count = try service.commentCount(for: task.id)
        #expect(count == 3)
    }

    @Test func commentCount_returnsZeroForNoComments() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        let count = try service.commentCount(for: task.id)
        #expect(count == 0)
    }

    // MARK: - Cross-context (T-73 regression)

    /// Reproduces the bug where a comment added via a task from a different
    /// ModelContext (like mainContext from @Query) wouldn't appear in an
    /// immediate fetchComments call on the service's own context.
    @Test func addComment_taskFromDifferentContext_immediatelyFetchable() throws {
        // Set up a shared container with two separate contexts,
        // simulating how the app has a service context and a mainContext.
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self])
        let config = ModelConfiguration(
            "CrossContext-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])

        // "mainContext" — analogous to the @Query context in the view layer
        let mainContext = container.mainContext

        // "serviceContext" — analogous to the separate ModelContext the service uses
        let serviceContext = ModelContext(container)
        let service = CommentService(modelContext: serviceContext)

        // Create a task in mainContext (simulating @Query producing the task)
        let project = Project(name: "Test", description: "", gitRepo: nil, colorHex: "#00FF00")
        mainContext.insert(project)
        let task = TransitTask(name: "Cross-context task", type: .bug, project: project, displayID: .permanent(99))
        mainContext.insert(task)
        try mainContext.save()

        // Add comment via the service, passing the mainContext task
        try service.addComment(
            to: task, content: "Should appear immediately", authorName: "Tester", isAgent: false
        )

        // Fetch comments from the service — this must return the new comment
        let comments = try service.fetchComments(for: task.id)
        #expect(comments.count == 1)
        #expect(comments[0].content == "Should appear immediately")
    }

    // MARK: - Batch Delete (T-85 regression)

    /// Reproduces the scenario where deleting multiple comments by IndexSet
    /// offsets could crash or delete the wrong items if the array was mutated
    /// between deletions. The fix uses `deleteComments(_:)` which collects
    /// IDs up front and deletes in a single save.
    @Test func deleteComments_batchRemovesCorrectItems() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        let commentA = try service.addComment(to: task, content: "A", authorName: "Alice", isAgent: false)
        _ = try service.addComment(to: task, content: "B", authorName: "Alice", isAgent: false)
        let commentC = try service.addComment(to: task, content: "C", authorName: "Alice", isAgent: false)

        // Delete first and third comments (simulating IndexSet offsets 0 and 2)
        try service.deleteComments([commentA, commentC])

        let remaining = try service.fetchComments(for: task.id)
        #expect(remaining.count == 1)
        #expect(remaining[0].content == "B")
    }

    @Test func deleteComments_emptyArrayIsNoOp() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)

        try service.addComment(to: task, content: "Keep me", authorName: "Alice", isAgent: false)
        try service.deleteComments([])

        let remaining = try service.fetchComments(for: task.id)
        #expect(remaining.count == 1)
    }

    // MARK: - Cascade Delete

    @Test func cascadeDelete_removesCommentsWhenTaskDeleted() throws {
        let (service, context) = try makeService()
        let task = makeTask(in: context)
        let taskID = task.id

        try service.addComment(to: task, content: "Will be deleted", authorName: "Alice", isAgent: false)
        #expect(try service.commentCount(for: taskID) == 1)

        context.delete(task)
        try context.save()

        let count = try service.commentCount(for: taskID)
        #expect(count == 0)
    }
}
