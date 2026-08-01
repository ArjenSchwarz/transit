import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskServiceStatusCommentFailureTests {

    @Test func saveFailureRollsBackStatusAndDeletesInsertedComment() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let service = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore()),
            statusSave: { _ in throw SaveFailure.simulated }
        )
        let commentService = CommentService(modelContext: context)
        let project = Project(
            name: "Test Project",
            description: nil,
            gitRepo: nil,
            colorHex: "#FF0000"
        )
        context.insert(project)
        let task = try await service.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        do {
            _ = try service.updateStatus(
                task: task,
                to: .planning,
                comment: "Must not survive",
                commentAuthor: "Agent",
                commentService: commentService
            )
            Issue.record("Expected SaveFailure to be thrown")
        } catch is SaveFailure {
            // Expected
        }

        #expect(task.status == .idea)
        #expect(try commentService.fetchComments(for: task.id).isEmpty)

        // A later unrelated save must not resurrect the failed comment.
        try context.save()
        #expect(try commentService.fetchComments(for: task.id).isEmpty)
    }
}
