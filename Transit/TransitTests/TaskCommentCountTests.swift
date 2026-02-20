import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression test for T-151: TaskCardView was running a per-card
/// `CommentService.commentCount(for:)` query in its view body, causing
/// N+1 database queries per render cycle. The fix uses the existing
/// `task.comments` relationship instead.
///
/// These tests verify that `task.comments?.count` returns the correct
/// count after adding/removing comments, which is the behaviour
/// TaskCardView now relies on.
@MainActor @Suite(.serialized)
struct TaskCommentCountTests {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        try TestModelContainer.newContext()
    }

    private func makeTask(in context: ModelContext) -> TransitTask {
        let project = Project(name: "Test", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(1))
        context.insert(task)
        return task
    }

    // MARK: - Relationship count

    @Test func commentsRelationshipCount_returnsZeroWhenNoComments() throws {
        let context = try makeContext()
        let task = makeTask(in: context)
        try context.save()

        #expect(task.comments?.count ?? 0 == 0)
    }

    @Test func commentsRelationshipCount_reflectsAddedComments() throws {
        let context = try makeContext()
        let task = makeTask(in: context)

        let comment1 = Comment(content: "First", authorName: "Alice", isAgent: false, task: task)
        context.insert(comment1)
        let comment2 = Comment(content: "Second", authorName: "Bob", isAgent: true, task: task)
        context.insert(comment2)
        try context.save()

        #expect(task.comments?.count == 2)
    }

    @Test func commentsRelationshipCount_decreasesAfterDeletion() throws {
        let context = try makeContext()
        let task = makeTask(in: context)

        let comment1 = Comment(content: "Keep", authorName: "Alice", isAgent: false, task: task)
        context.insert(comment1)
        let comment2 = Comment(content: "Delete", authorName: "Bob", isAgent: false, task: task)
        context.insert(comment2)
        try context.save()

        #expect(task.comments?.count == 2)

        context.delete(comment2)
        try context.save()

        #expect(task.comments?.count == 1)
    }

    @Test func commentsRelationshipCount_isNilNotCount_whenNoRelationshipLoaded() throws {
        // Verify that the optional binding pattern `if let count = task.comments?.count`
        // used in TaskCardView behaves correctly for a newly created task.
        let context = try makeContext()
        let task = makeTask(in: context)

        // A newly inserted task may have nil comments before any are added.
        // The badge should not appear for count == 0 or nil.
        let count = task.comments?.count ?? 0
        #expect(count == 0)
    }
}
