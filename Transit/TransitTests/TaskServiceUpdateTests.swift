import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskServiceUpdateTests {

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

    // MARK: - updateTask

    @Test func updateTaskAppliesAllFields() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Original", description: "Old desc", type: .feature, project: project
        )

        try service.updateTask(
            task,
            name: "Updated",
            description: "New desc",
            type: .bug,
            metadata: ["key": "value"]
        )

        #expect(task.name == "Updated")
        #expect(task.taskDescription == "New desc")
        #expect(task.type == .bug)
        #expect(task.metadata["key"] == "value")
    }

    @Test func updateTaskAppliesOnlyProvidedFields() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Original", description: "Keep this", type: .feature, project: project
        )

        try service.updateTask(task, name: "Changed")

        #expect(task.name == "Changed")
        #expect(task.taskDescription == "Keep this")
        #expect(task.type == .feature)
    }

    @Test func updateTaskRejectsEmptyName() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Valid", description: nil, type: .feature, project: project
        )

        #expect(throws: TaskService.Error.invalidName) {
            try service.updateTask(task, name: "   ")
        }
        #expect(task.name == "Valid", "Name should not change on validation failure")
    }

    @Test func updateTaskDefersSaveWhenFlagIsFalse() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Original", description: nil, type: .feature, project: project
        )

        try service.updateTask(task, name: "Deferred", save: false)

        #expect(task.name == "Deferred")
        // The in-memory mutation is applied but we verify the save: false path
        // doesn't throw by reaching this point without error.
    }
}
