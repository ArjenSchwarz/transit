import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct AddTaskIntentTests {
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

    private func makeEntity(from project: Project) -> ProjectEntity {
        ProjectEntity.from(project)
    }

    @Test func executeCreatesTaskAndReturnsStructuredResult() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let result = try await AddTaskIntent.execute(
            name: "New Visual Task",
            taskDescription: "Task description",
            type: .feature,
            project: makeEntity(from: project),
            services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
        )

        #expect(result.taskId.uuidString.isEmpty == false)
        #expect(result.status == "idea")
        #expect(result.projectId == project.id)
        #expect(result.projectName == project.name)

        let allTasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(allTasks.count == 1)
        #expect(allTasks[0].status == .idea)
        #expect(allTasks[0].name == "New Visual Task")
    }

    @Test func executeTrimsTaskNameBeforeCreation() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        _ = try await AddTaskIntent.execute(
            name: "  Trim me  ",
            taskDescription: nil,
            type: .bug,
            project: makeEntity(from: project),
            services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
        )

        let allTasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(allTasks.count == 1)
        #expect(allTasks[0].name == "Trim me")
    }

    // Regression for T-1178: the visual AddTaskIntent must not declare a
    // metadata @Parameter (see Decision 17 in
    // shortcuts-friendly-intents/decision_log.md). Reflect on a fresh intent
    // instance and assert no `metadata` property exists. This fails against
    // the buggy implementation that exposed `var metadata: String?` and
    // passes once the parameter is removed.
    @Test func addTaskIntentDoesNotDeclareMetadataParameter() {
        let intent = AddTaskIntent()
        let mirror = Mirror(reflecting: intent)
        let propertyNames = mirror.children.compactMap { $0.label }
        // App Intents synthesises backing storage with a leading underscore
        // for @Parameter properties, so inspect both forms.
        let normalised = propertyNames.map { name -> String in
            name.hasPrefix("_") ? String(name.dropFirst()) : name
        }
        #expect(normalised.contains("metadata") == false,
                "AddTaskIntent must not declare a metadata @Parameter (see Decision 17)")
    }

    // Regression for T-1178: the visual AddTaskIntent must not expose a metadata
    // parameter (see Decision 17 in shortcuts-friendly-intents/decision_log.md).
    // A task created via the visual intent has empty metadata.
    @Test func executeDoesNotAcceptMetadataAndCreatesEmptyMetadataTask() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        // Note: deliberately no `metadata:` argument. Reintroducing the parameter
        // would require this call site to change, and the test below would no
        // longer guarantee the resulting task has empty metadata.
        let result = try await AddTaskIntent.execute(
            name: "Plain Task",
            taskDescription: "Description, with a comma and key=value-like text",
            type: .feature,
            project: makeEntity(from: project),
            services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
        )

        let allTasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(allTasks.count == 1)
        #expect(allTasks[0].id == result.taskId)
        #expect(allTasks[0].metadata.isEmpty)
    }

    @Test func executeThrowsInvalidInputForEmptyName() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        await #expect(throws: VisualIntentError.self) {
            _ = try await AddTaskIntent.execute(
                name: "   ",
                taskDescription: nil,
                type: .chore,
                project: makeEntity(from: project),
                services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
            )
        }
    }

    @Test func executeThrowsNoProjectsWhenDatabaseIsEmpty() async throws {
        let svc = try makeServices()
        let fakeProject = ProjectEntity(
            id: UUID().uuidString,
            projectId: UUID(),
            name: "Missing"
        )

        do {
            _ = try await AddTaskIntent.execute(
                name: "Task",
                taskDescription: nil,
                type: .feature,
                project: fakeProject,
                services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
            )
            Issue.record("Expected noProjects error")
        } catch let error as VisualIntentError {
            switch error {
            case .noProjects:
                break
            default:
                Issue.record("Expected noProjects error, got \(error.code)")
            }
        }
    }

    @Test func executeThrowsProjectNotFoundForStaleProjectSelection() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let selectedProject = makeEntity(from: project)
        svc.context.delete(project)
        try svc.context.save()

        await #expect(throws: VisualIntentError.self) {
            _ = try await AddTaskIntent.execute(
                name: "Task",
                taskDescription: nil,
                type: .feature,
                project: selectedProject,
                services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
            )
        }
    }
}
