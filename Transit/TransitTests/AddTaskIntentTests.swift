import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct AddTaskIntentTests {

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
    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    private func makeProjectEntity(from project: Project) -> ProjectEntity {
        ProjectEntity.from(project)
    }

    private func makeInput(
        name: String,
        taskDescription: String? = nil,
        type: TaskType = .feature,
        project: ProjectEntity
    ) -> AddTaskIntent.Input {
        AddTaskIntent.Input(
            name: name,
            taskDescription: taskDescription,
            type: type,
            project: project
        )
    }

    // MARK: - Success Cases

    @Test func successfulCreationReturnsCorrectResult() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = makeProjectEntity(from: project)

        let result = try await AddTaskIntent.execute(
            input: makeInput(name: "New Task", taskDescription: "A description", project: entity),
            taskService: svc.task,
            projectService: svc.project
        )

        #expect(result.status == "idea")
        #expect(result.projectId == project.id)
        #expect(result.projectName == "Test Project")
        #expect(result.displayId != nil)
    }

    @Test func taskCreatedWithStatusIdea() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = makeProjectEntity(from: project)

        let result = try await AddTaskIntent.execute(
            input: makeInput(name: "Status Check Task", type: .bug, project: entity),
            taskService: svc.task,
            projectService: svc.project
        )

        #expect(result.status == "idea")
    }

    @Test func taskCreatedWithNilDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = makeProjectEntity(from: project)

        let result = try await AddTaskIntent.execute(
            input: makeInput(name: "No Description Task", type: .chore, project: entity),
            taskService: svc.task,
            projectService: svc.project
        )

        #expect(result.taskId != UUID())
        #expect(result.status == "idea")
    }

    @Test func resultContainsAllRequiredFields() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = makeProjectEntity(from: project)

        let result = try await AddTaskIntent.execute(
            input: makeInput(name: "Complete Result Task", taskDescription: "Full description",
                             type: .research, project: entity),
            taskService: svc.task,
            projectService: svc.project
        )

        #expect(result.id == result.taskId.uuidString)
        #expect(result.status == "idea")
        #expect(result.projectId == project.id)
        #expect(result.projectName == project.name)
    }

    // MARK: - Error Cases

    @Test func emptyNameThrowsInvalidInput() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = makeProjectEntity(from: project)

        await #expect(throws: VisualIntentError.self) {
            try await AddTaskIntent.execute(
                input: makeInput(name: "", project: entity),
                taskService: svc.task,
                projectService: svc.project
            )
        }
    }

    @Test func whitespaceOnlyNameThrowsInvalidInput() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = makeProjectEntity(from: project)

        await #expect(throws: VisualIntentError.self) {
            try await AddTaskIntent.execute(
                input: makeInput(name: "   \t\n  ", project: entity),
                taskService: svc.task,
                projectService: svc.project
            )
        }
    }

    @Test func projectNotFoundThrowsError() async throws {
        let svc = try makeServices()
        makeProject(in: svc.context, name: "Existing")
        let fakeEntity = ProjectEntity(
            id: UUID().uuidString,
            projectId: UUID(),
            name: "Deleted Project"
        )

        await #expect(throws: VisualIntentError.self) {
            try await AddTaskIntent.execute(
                input: makeInput(name: "Orphaned Task", project: fakeEntity),
                taskService: svc.task,
                projectService: svc.project
            )
        }
    }

    @Test func noProjectsExistThrowsNoProjects() async throws {
        let svc = try makeServices()
        let fakeEntity = ProjectEntity(
            id: UUID().uuidString,
            projectId: UUID(),
            name: "Ghost Project"
        )

        await #expect(throws: VisualIntentError.self) {
            try await AddTaskIntent.execute(
                input: makeInput(name: "Task Without Projects", project: fakeEntity),
                taskService: svc.task,
                projectService: svc.project
            )
        }
    }

    // MARK: - Integration with TaskService

    @Test func taskIsPersistableViaTaskService() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = makeProjectEntity(from: project)

        let result = try await AddTaskIntent.execute(
            input: makeInput(name: "Persisted Task", taskDescription: "Should be saved",
                             type: .documentation, project: entity),
            taskService: svc.task,
            projectService: svc.project
        )

        let foundTask = try svc.task.findByID(result.taskId)
        #expect(foundTask.name == "Persisted Task")
        #expect(foundTask.taskDescription == "Should be saved")
        #expect(foundTask.status == .idea)
        #expect(foundTask.type == .documentation)
    }

    @Test func nameIsTrimmedBeforeCreation() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = makeProjectEntity(from: project)

        let result = try await AddTaskIntent.execute(
            input: makeInput(name: "  Trimmed Task  ", project: entity),
            taskService: svc.task,
            projectService: svc.project
        )

        let foundTask = try svc.task.findByID(result.taskId)
        #expect(foundTask.name == "Trimmed Task")
    }
}
