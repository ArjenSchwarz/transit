import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct AddTaskIntentIntegrationTests {
    private struct Services {
        let task: TaskService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String = "Integration Project") -> Project {
        let project = Project(name: name, description: "desc", gitRepo: nil, colorHex: "#00AAFF")
        context.insert(project)
        return project
    }

    @Test func addTaskIntentCreatesPersistedTaskWithMatchingResultFields() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let result = try await AddTaskIntent.execute(
            name: "Integration Task",
            taskDescription: "From integration test",
            type: .documentation,
            project: ProjectEntity.from(project),
            services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
        )

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 1)

        let persisted = tasks[0]
        #expect(persisted.id == result.taskId)
        #expect(persisted.statusRawValue == result.status)
        #expect(persisted.project?.id == result.projectId)
        #expect(persisted.project?.name == result.projectName)
    }

    @Test func addTaskIntentCreatesIdeaTaskVisibleToTaskEntityQuery() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let result = try await AddTaskIntent.execute(
            name: "Queryable Task",
            taskDescription: nil,
            type: .research,
            project: ProjectEntity.from(project),
            services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
        )

        let entities = TaskEntityQuery.entities(for: [result.taskId.uuidString], modelContext: svc.context)
        #expect(entities.count == 1)
        #expect(entities[0].name == "Queryable Task")
        #expect(entities[0].status == "idea")
    }

    @Test func addTaskIntentPersistsMetadataFromInputString() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        _ = try await AddTaskIntent.execute(
            name: "Metadata Integration Task",
            taskDescription: nil,
            type: .feature,
            project: ProjectEntity.from(project),
            metadata: "priority=high,source=shortcut",
            services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
        )

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 1)
        #expect(tasks[0].metadata["priority"] == "high")
        #expect(tasks[0].metadata["source"] == "shortcut")
    }
}
