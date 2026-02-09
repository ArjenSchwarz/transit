import CloudKit
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskServiceTests {

    // MARK: - Helpers

    private func makeService() throws -> (TaskService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let allocator = DisplayIDAllocator(container: CKContainer.default())
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

        // In a test environment without CloudKit, this will fall back to provisional.
        // Either outcome is valid — the important thing is a display ID is assigned.
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

    // MARK: - updateStatus

    @Test func updateStatusChangesStatusAndAppliesSideEffects() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(name: "Task", description: nil, type: .feature, project: project)

        service.updateStatus(task: task, to: .planning)
        #expect(task.status == .planning)
        #expect(task.completionDate == nil)

        service.updateStatus(task: task, to: .done)
        #expect(task.status == .done)
        #expect(task.completionDate != nil)
    }

    // MARK: - abandon

    @Test func abandonSetsStatusToAbandonedWithCompletionDate() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(name: "Task", description: nil, type: .feature, project: project)

        service.abandon(task: task)

        #expect(task.status == .abandoned)
        #expect(task.completionDate != nil)
    }

    // MARK: - restore

    @Test func restoreSetsStatusToIdeaAndClearsCompletionDate() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(name: "Task", description: nil, type: .feature, project: project)

        service.abandon(task: task)
        #expect(task.completionDate != nil)

        service.restore(task: task)
        #expect(task.status == .idea)
        #expect(task.completionDate == nil)
    }

    // MARK: - findByDisplayID

    @Test func findByDisplayIDReturnsCorrectTask() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        let task = TransitTask(name: "Findable", type: .feature, project: project, displayID: .permanent(99))
        StatusEngine.initializeNewTask(task)
        context.insert(task)

        let found = service.findByDisplayID(99)
        #expect(found?.name == "Findable")
    }

    @Test func findByDisplayIDReturnsNilForNonExistentID() throws {
        let (service, _) = try makeService()

        let found = service.findByDisplayID(999)
        #expect(found == nil)
    }
}
