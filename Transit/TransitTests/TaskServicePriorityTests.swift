import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskServicePriorityTests {

    // MARK: - Helpers

    private func makeService() throws -> (TaskService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        return (service, context)
    }

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test Project", description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    // MARK: - createTask

    @Test func createTaskDefaultsToMediumPriority() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        let task = try await service.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        #expect(task.priority == .medium)
    }

    @Test func createTaskHonorsExplicitPriority() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        let task = try await service.createTask(
            name: "Task", description: nil, type: .feature, project: project, priority: .high
        )

        #expect(task.priority == .high)
    }

    @Test func createTaskByProjectIDHonorsExplicitPriority() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        let task = try await service.createTask(
            name: "Task", description: nil, type: .feature, projectID: project.id, priority: .low
        )

        #expect(task.priority == .low)
    }

    // MARK: - updateTask

    @Test func updateTaskSetsPriority() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        try service.updateTask(task, priority: .high)

        #expect(task.priority == .high)
    }

    // Decision 8: omitting priority on update leaves it unchanged.
    @Test func updateTaskOmittingPriorityLeavesItUnchanged() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Task", description: nil, type: .feature, project: project, priority: .high
        )

        // An unrelated update that omits priority must not reset it to medium.
        try service.updateTask(task, name: "Renamed")

        #expect(task.name == "Renamed")
        #expect(task.priority == .high)
    }
}
