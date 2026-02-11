import Foundation
import SwiftData
import Testing
@testable import Transit

/// Integration tests: AddTaskIntent creates tasks, FindTasksIntent retrieves them.
/// Verifies the full visual intent flow end-to-end.
@MainActor @Suite(.serialized)
struct FindTasksIntegrationTests {

    // MARK: - Helpers

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
    private func makeProject(in context: ModelContext, name: String? = nil) -> Project {
        let projectName = name ?? "FTI-Integ-\(UUID().uuidString.prefix(8))"
        let project = Project(name: projectName, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    private func createTask(
        name: String,
        type: TaskType = .feature,
        project: Project,
        services: Services
    ) async throws -> TaskCreationResult {
        let entity = ProjectEntity.from(project)
        let input = AddTaskIntent.Input(
            name: name,
            taskDescription: nil,
            type: type,
            project: entity
        )
        return try await AddTaskIntent.execute(
            input: input,
            taskService: services.task,
            projectService: services.project
        )
    }

    private func findInput(
        type: TaskType? = nil,
        project: ProjectEntity? = nil,
        status: TaskStatus? = nil,
        completionDateFilter: DateFilterOption? = nil,
        lastChangedFilter: DateFilterOption? = nil
    ) -> FindTasksIntent.Input {
        FindTasksIntent.Input(
            type: type,
            project: project,
            status: status,
            completionDateFilter: completionDateFilter,
            lastChangedFilter: lastChangedFilter,
            completionFromDate: nil,
            completionToDate: nil,
            lastChangedFromDate: nil,
            lastChangedToDate: nil
        )
    }

    // MARK: - AddTask → FindTasks Flow

    @Test func createdTaskFoundByFindTasks() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let createResult = try await createTask(
            name: "Integration Task", type: .bug, project: project, services: svc
        )

        let entityP = ProjectEntity.from(project)
        let found = try FindTasksIntent.execute(
            input: findInput(project: entityP),
            modelContext: svc.context
        )

        #expect(found.count == 1)
        #expect(found.first?.taskId == createResult.taskId)
        #expect(found.first?.name == "Integration Task")
        #expect(found.first?.type == "bug")
        #expect(found.first?.status == "idea")
    }

    @Test func createdTasksFilteredByType() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        _ = try await createTask(name: "Bug Task", type: .bug, project: project, services: svc)
        _ = try await createTask(name: "Feature Task", type: .feature, project: project, services: svc)

        let entityP = ProjectEntity.from(project)
        let bugResults = try FindTasksIntent.execute(
            input: findInput(type: .bug, project: entityP),
            modelContext: svc.context
        )

        #expect(bugResults.count == 1)
        #expect(bugResults.first?.name == "Bug Task")
    }

    @Test func createdTasksFilteredByProject() async throws {
        let svc = try makeServices()
        let projectA = makeProject(in: svc.context, name: "Project A")
        let projectB = makeProject(in: svc.context, name: "Project B")

        _ = try await createTask(name: "Task A", project: projectA, services: svc)
        _ = try await createTask(name: "Task B", project: projectB, services: svc)

        let entityA = ProjectEntity.from(projectA)
        let results = try FindTasksIntent.execute(
            input: findInput(project: entityA),
            modelContext: svc.context
        )

        #expect(results.count == 1)
        #expect(results.first?.name == "Task A")
        #expect(results.first?.projectName == "Project A")
    }

    @Test func findTasksWithStatusFilterAfterStatusChange() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let result = try await createTask(name: "Moving Task", project: project, services: svc)

        // Move to in-progress via TaskService
        let task = try svc.task.findByID(result.taskId)
        try svc.task.updateStatus(task: task, to: .inProgress)

        let entityP = ProjectEntity.from(project)
        let inProgressResults = try FindTasksIntent.execute(
            input: findInput(project: entityP, status: .inProgress),
            modelContext: svc.context
        )

        #expect(inProgressResults.count == 1)
        #expect(inProgressResults.first?.name == "Moving Task")
        #expect(inProgressResults.first?.status == "in-progress")
    }

    @Test func findTasksLastChangedFilterToday() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        _ = try await createTask(name: "New Task", project: project, services: svc)

        let entityP = ProjectEntity.from(project)
        let results = try FindTasksIntent.execute(
            input: findInput(project: entityP, lastChangedFilter: .today),
            modelContext: svc.context
        )

        #expect(results.count == 1)
        #expect(results.first?.name == "New Task")
    }

    @Test func findTasksReturnsEmptyArrayWhenNoMatches() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        _ = try await createTask(name: "Bug Task", type: .bug, project: project, services: svc)

        let entityP = ProjectEntity.from(project)
        let results = try FindTasksIntent.execute(
            input: findInput(type: .chore, project: entityP),
            modelContext: svc.context
        )

        #expect(results.isEmpty)
    }

    @Test func findTasksEntityPropertiesMatchCreatedTask() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let createResult = try await createTask(
            name: "Full Check", type: .research, project: project, services: svc
        )

        let entityP = ProjectEntity.from(project)
        let found = try FindTasksIntent.execute(
            input: findInput(project: entityP),
            modelContext: svc.context
        )

        let entity = try #require(found.first)
        #expect(entity.id == createResult.taskId.uuidString)
        #expect(entity.taskId == createResult.taskId)
        #expect(entity.displayId == createResult.displayId)
        #expect(entity.name == "Full Check")
        #expect(entity.status == "idea")
        #expect(entity.type == "research")
        #expect(entity.projectId == project.id)
        #expect(entity.projectName == project.name)
    }
}
