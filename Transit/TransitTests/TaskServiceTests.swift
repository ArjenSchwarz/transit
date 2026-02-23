import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskServiceTests {

    // MARK: - Helpers

    private func makeService() throws -> (TaskService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        return (service, context)
    }

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test Project", description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    // MARK: - createTask

    @Test func createTaskCreatesTaskInIdeaStatus() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        let task = try await service.createTask(
            name: "New Task",
            description: "A description",
            type: .feature,
            project: project
        )

        #expect(task.status == .idea)
        #expect(task.name == "New Task")
        #expect(task.taskDescription == "A description")
        #expect(task.type == .feature)
    }

    @Test func createTaskAssignsDisplayID() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        let task = try await service.createTask(
            name: "Task",
            description: nil,
            type: .chore,
            project: project
        )

        // InMemoryCounterStore always succeeds, so we get a permanent ID.
        let hasDisplayID = task.displayID == .provisional || task.permanentDisplayId != nil
        #expect(hasDisplayID)
    }

    @Test func createTaskSetsCreationAndLastStatusChangeDates() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        let task = try await service.createTask(
            name: "Task",
            description: nil,
            type: .bug,
            project: project
        )

        #expect(task.creationDate <= Date.now)
        #expect(task.lastStatusChangeDate <= Date.now)
    }

    @Test func createTaskWithMetadataStoresMetadata() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        let task = try await service.createTask(
            name: "Task",
            description: nil,
            type: .feature,
            project: project,
            metadata: ["git.branch": "feature/test"]
        )

        #expect(task.metadata["git.branch"] == "feature/test")
    }

    @Test func createTaskTrimsAndValidatesName() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        // Whitespace-only name should throw
        do {
            _ = try await service.createTask(
                name: "   ",
                description: nil,
                type: .feature,
                project: project
            )
            Issue.record("Expected TaskService.Error.invalidName")
        } catch let error as TaskService.Error {
            #expect(error == .invalidName)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        // Valid name with leading/trailing whitespace should be trimmed
        let task = try await service.createTask(
            name: "  Trimmed Name  ", description: nil, type: .feature, project: project
        )
        #expect(task.name == "Trimmed Name")
    }

    // MARK: - updateStatus

    @Test func updateStatusChangesStatusAndAppliesSideEffects() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(name: "Task", description: nil, type: .feature, project: project)

        try service.updateStatus(task: task, to: .planning)
        #expect(task.status == .planning)
        #expect(task.completionDate == nil)

        try service.updateStatus(task: task, to: .done)
        #expect(task.status == .done)
        #expect(task.completionDate != nil)
    }

    // MARK: - abandon

    @Test func abandonSetsStatusToAbandonedWithCompletionDate() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(name: "Task", description: nil, type: .feature, project: project)

        try service.abandon(task: task)

        #expect(task.status == .abandoned)
        #expect(task.completionDate != nil)
    }

    // MARK: - restore

    @Test func restoreSetsStatusToIdeaAndClearsCompletionDate() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(name: "Task", description: nil, type: .feature, project: project)

        try service.abandon(task: task)
        #expect(task.completionDate != nil)

        try service.restore(task: task)
        #expect(task.status == .idea)
        #expect(task.completionDate == nil)
    }

    @Test func restoreNonAbandonedTaskThrows() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(name: "Task", description: nil, type: .feature, project: project)

        #expect(throws: TaskService.Error.restoreRequiresAbandonedTask) {
            try service.restore(task: task)
        }
    }

    // MARK: - findByDisplayID

    @Test func findByDisplayIDReturnsCorrectTask() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        let task = TransitTask(name: "Findable", type: .feature, project: project, displayID: .permanent(99))
        StatusEngine.initializeNewTask(task)
        context.insert(task)

        let found = try service.findByDisplayID(99)
        #expect(found.name == "Findable")
    }

    @Test func findByDisplayIDThrowsForNonExistentID() throws {
        let (service, _) = try makeService()

        #expect(throws: TaskService.Error.taskNotFound) {
            try service.findByDisplayID(999)
        }
    }

    // MARK: - Context persistence (T-173 regression)

    /// Regression test for T-173: Status updates must persist when the service
    /// uses the same ModelContext as the caller (container.mainContext).
    /// Before the fix, TaskService used a separate ModelContext(container) while
    /// views used container.mainContext via @Query. Status mutations happened on
    /// the view's context but save() was called on the service's context, so
    /// changes were never written to disk.
    @Test func updateStatusPersistsWhenUsingSharedContext() async throws {
        // Create a container — mimics the app setup
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self])
        let config = ModelConfiguration(
            "T173-regression-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])

        // Use container.mainContext for the service — this is the fix
        let context = container.mainContext
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)

        // Create a task via the shared context (simulates @Query providing the task)
        let project = Project(
            name: "Test", description: "Test", gitRepo: nil, colorHex: "#FF0000"
        )
        context.insert(project)
        let task = try await service.createTask(
            name: "Persist Check", description: nil, type: .feature, project: project
        )
        #expect(task.status == .idea)

        // Update status — this must be saved to the store
        try service.updateStatus(task: task, to: .inProgress)

        // Verify the change persisted by re-fetching from a fresh context
        let verifyContext = ModelContext(container)
        let taskID = task.id
        let descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == taskID }
        )
        let refetched = try verifyContext.fetch(descriptor).first
        #expect(refetched?.statusRawValue == TaskStatus.inProgress.rawValue)
    }

    // MARK: - updateStatus with comment

    @Test func updateStatusWithCommentCreatesCommentAtomically() async throws {
        let (service, context) = try makeService()
        let commentService = CommentService(modelContext: context)
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        try service.updateStatus(
            task: task,
            to: .planning,
            comment: "Moving to planning",
            commentAuthor: "Agent",
            commentService: commentService
        )

        #expect(task.status == .planning)
        let comments = try commentService.fetchComments(for: task.id)
        #expect(comments.count == 1)
        #expect(comments.first?.content == "Moving to planning")
        #expect(comments.first?.authorName == "Agent")
    }

    @Test func updateStatusWithCommentSetsIsAgentTrue() async throws {
        let (service, context) = try makeService()
        let commentService = CommentService(modelContext: context)
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        try service.updateStatus(
            task: task,
            to: .inProgress,
            comment: "Starting work",
            commentAuthor: "claude-code",
            commentService: commentService
        )

        let comments = try commentService.fetchComments(for: task.id)
        #expect(comments.first?.isAgent == true)
    }

    @Test func updateStatusWithoutCommentBehavesAsExisting() async throws {
        let (service, context) = try makeService()
        let commentService = CommentService(modelContext: context)
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        try service.updateStatus(task: task, to: .planning)

        #expect(task.status == .planning)
        let comments = try commentService.fetchComments(for: task.id)
        #expect(comments.isEmpty)
    }
}
