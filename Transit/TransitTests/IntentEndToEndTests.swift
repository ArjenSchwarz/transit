import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

/// End-to-end tests exercising the full intent flow across all three visual intents
/// and verifying cross-intent interactions. [Task 14]
@MainActor @Suite(.serialized)
struct IntentEndToEndTests {

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

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func findInput(
        type: TaskType? = nil,
        project: ProjectEntity? = nil,
        status: TaskStatus? = nil
    ) -> FindTasksIntent.Input {
        FindTasksIntent.Input(
            type: type, project: project, status: status,
            completionDateFilter: nil, lastChangedFilter: nil,
            completionFromDate: nil, completionToDate: nil,
            lastChangedFromDate: nil, lastChangedToDate: nil
        )
    }

    // MARK: - 14.1: Cross-Intent E2E Flow

    @Test func addTaskThenFindViaBothIntents() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = ProjectEntity.from(project)

        // Create task via visual AddTaskIntent
        let createResult = try await AddTaskIntent.execute(
            input: AddTaskIntent.Input(
                name: "E2E Test Task",
                taskDescription: "Created for end-to-end testing",
                type: .bug,
                project: entity
            ),
            taskService: svc.task,
            projectService: svc.project
        )

        // Retrieve via visual FindTasksIntent — filter by project to isolate from other test data
        let findResults = try FindTasksIntent.execute(
            input: findInput(type: .bug, project: entity),
            modelContext: svc.context
        )

        #expect(findResults.contains { $0.taskId == createResult.taskId })
        #expect(findResults.contains { $0.name == "E2E Test Task" })

        // Retrieve via JSON QueryTasksIntent
        let queryResult = QueryTasksIntent.execute(
            input: "{\"type\":\"bug\",\"projectId\":\"\(project.id.uuidString)\"}",
            projectService: svc.project,
            modelContext: svc.context
        )
        let queryParsed = try parseJSONArray(queryResult)
        #expect(queryParsed.contains { $0["name"] as? String == "E2E Test Task" })
    }

    @Test func addTaskUpdateStatusThenFind() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = ProjectEntity.from(project)

        // Create via AddTaskIntent
        let createResult = try await AddTaskIntent.execute(
            input: AddTaskIntent.Input(
                name: "Status Flow Task", taskDescription: nil,
                type: .feature, project: entity
            ),
            taskService: svc.task, projectService: svc.project
        )

        // Update status via UpdateStatusIntent (JSON-based)
        let updateInput = "{\"taskId\":\"\(createResult.taskId.uuidString)\",\"status\":\"in-progress\"}"
        let updateResult = UpdateStatusIntent.execute(
            input: updateInput, taskService: svc.task
        )
        let updateParsed = try parseJSON(updateResult)
        #expect(updateParsed["previousStatus"] as? String == "idea")
        #expect(updateParsed["status"] as? String == "in-progress")

        // Find via visual FindTasksIntent with status + project filter
        let findResults = try FindTasksIntent.execute(
            input: findInput(project: entity, status: .inProgress),
            modelContext: svc.context
        )

        #expect(findResults.contains { $0.name == "Status Flow Task" && $0.status == "in-progress" })
    }

    @Test func createViaJSONThenFindViaVisual() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        // Create via JSON CreateTaskIntent
        let jsonInput = """
        {"projectId":"\(project.id.uuidString)","name":"JSON Created","type":"chore"}
        """
        let jsonResult = await CreateTaskIntent.execute(
            input: jsonInput, taskService: svc.task, projectService: svc.project
        )
        let jsonParsed = try parseJSON(jsonResult)
        let taskId = try #require(jsonParsed["taskId"] as? String)

        // Find via visual FindTasksIntent — filter by project to isolate
        let entity = ProjectEntity.from(project)
        let findResults = try FindTasksIntent.execute(
            input: findInput(type: .chore, project: entity),
            modelContext: svc.context
        )

        #expect(findResults.contains { $0.id == taskId })
        #expect(findResults.contains { $0.type == "chore" })
    }

    @Test func multipleTasksCreatedAndFilteredCorrectly() async throws {
        let svc = try makeServices()
        let projectA = makeProject(in: svc.context, name: "AlphaE2E")
        let projectB = makeProject(in: svc.context, name: "BetaE2E")
        let entityA = ProjectEntity.from(projectA)
        let entityB = ProjectEntity.from(projectB)

        // Create tasks across projects and types
        _ = try await AddTaskIntent.execute(
            input: AddTaskIntent.Input(
                name: "Bug in Alpha", taskDescription: nil,
                type: .bug, project: entityA
            ),
            taskService: svc.task, projectService: svc.project
        )
        _ = try await AddTaskIntent.execute(
            input: AddTaskIntent.Input(
                name: "Feature in Alpha", taskDescription: nil,
                type: .feature, project: entityA
            ),
            taskService: svc.task, projectService: svc.project
        )
        _ = try await AddTaskIntent.execute(
            input: AddTaskIntent.Input(
                name: "Bug in Beta", taskDescription: nil,
                type: .bug, project: entityB
            ),
            taskService: svc.task, projectService: svc.project
        )

        // Filter by type AND project to isolate from other test data
        let bugsInAlpha = try FindTasksIntent.execute(
            input: findInput(type: .bug, project: entityA), modelContext: svc.context
        )
        #expect(bugsInAlpha.count == 1)
        #expect(bugsInAlpha.first?.name == "Bug in Alpha")

        // Filter by project only
        let alphaResults = try FindTasksIntent.execute(
            input: findInput(project: entityA), modelContext: svc.context
        )
        #expect(alphaResults.count == 2)

        // Filter by type AND project B
        let bugsInBeta = try FindTasksIntent.execute(
            input: findInput(type: .bug, project: entityB), modelContext: svc.context
        )
        #expect(bugsInBeta.count == 1)
        #expect(bugsInBeta.first?.name == "Bug in Beta")
    }

    // MARK: - 14.2: Intent Discoverability

    @Test func transitShortcutsRegistersAllFiveIntents() {
        let shortcuts = TransitShortcuts.appShortcuts
        #expect(shortcuts.count == 5)
    }

    @Test func allIntentsHaveCorrectTitles() {
        #expect(String(localized: CreateTaskIntent.title) == "Transit: Create Task")
        #expect(String(localized: UpdateStatusIntent.title) == "Transit: Update Status")
        #expect(String(localized: QueryTasksIntent.title) == "Transit: Query Tasks")
        #expect(String(localized: AddTaskIntent.title) == "Transit: Add Task")
        #expect(String(localized: FindTasksIntent.title) == "Transit: Find Tasks")
    }

    // MARK: - 14.3: Error Handling E2E

    @Test func addTaskWithNoProjectsThrowsNoProjects() async throws {
        let svc = try makeServices()
        let fakeEntity = ProjectEntity(id: UUID().uuidString, projectId: UUID(), name: "Ghost")

        await #expect(throws: VisualIntentError.self) {
            try await AddTaskIntent.execute(
                input: AddTaskIntent.Input(
                    name: "Orphan", taskDescription: nil, type: .feature, project: fakeEntity
                ),
                taskService: svc.task, projectService: svc.project
            )
        }
    }

    @Test func addTaskWithDeletedProjectThrowsProjectNotFound() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        _ = project
        let fakeEntity = ProjectEntity(id: UUID().uuidString, projectId: UUID(), name: "Deleted")

        await #expect(throws: VisualIntentError.self) {
            try await AddTaskIntent.execute(
                input: AddTaskIntent.Input(
                    name: "Orphan", taskDescription: nil, type: .feature, project: fakeEntity
                ),
                taskService: svc.task, projectService: svc.project
            )
        }
    }

    @Test func addTaskWithEmptyNameThrowsInvalidInput() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = ProjectEntity.from(project)

        await #expect(throws: VisualIntentError.self) {
            try await AddTaskIntent.execute(
                input: AddTaskIntent.Input(
                    name: "", taskDescription: nil, type: .feature, project: entity
                ),
                taskService: svc.task, projectService: svc.project
            )
        }
    }

    @Test func findTasksWithNoMatchReturnsEmptyArray() throws {
        let svc = try makeServices()
        // Use a unique project filter to ensure no matches from other tests
        let project = makeProject(in: svc.context, name: "EmptyProjectE2E")
        let entity = ProjectEntity.from(project)

        let results = try FindTasksIntent.execute(
            input: findInput(type: .documentation, project: entity),
            modelContext: svc.context
        )
        #expect(results.isEmpty)
    }

    @Test func queryTasksWithInvalidJSONReturnsErrorJSON() throws {
        let svc = try makeServices()
        let result = QueryTasksIntent.execute(
            input: "not valid json",
            projectService: svc.project,
            modelContext: svc.context
        )
        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func updateStatusWithBadDisplayIdReturnsTaskNotFound() throws {
        let svc = try makeServices()
        let result = UpdateStatusIntent.execute(
            input: "{\"displayId\":99999,\"status\":\"planning\"}",
            taskService: svc.task
        )
        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "TASK_NOT_FOUND")
    }

    @Test func updateStatusWithInvalidStatusReturnsInvalidStatus() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(1))
        StatusEngine.initializeNewTask(task)
        svc.context.insert(task)

        let result = UpdateStatusIntent.execute(
            input: "{\"displayId\":1,\"status\":\"nonexistent\"}",
            taskService: svc.task
        )
        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
    }

}
