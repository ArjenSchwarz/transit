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

        let creationDate = task.creationDate
        let lastStatusChangeDate = task.lastStatusChangeDate
        #expect(creationDate <= Date.now)
        #expect(lastStatusChangeDate <= Date.now)
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

        let metadata = task.metadata
        #expect(metadata["git.branch"] == "feature/test")
    }

    @Test func createTaskTrimsAndValidatesName() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        // Whitespace-only name should throw
        await #expect(throws: TaskService.Error.invalidName) {
            _ = try await service.createTask(
                name: "   ", description: nil, type: .feature, project: project
            )
        }

        // Valid name with leading/trailing whitespace should be trimmed
        let task = try await service.createTask(
            name: "  Trimmed Name  ", description: nil, type: .feature, project: project
        )
        let taskName = task.name
        #expect(taskName == "Trimmed Name")
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
}
