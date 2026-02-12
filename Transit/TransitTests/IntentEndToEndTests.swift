import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

/// End-to-end tests exercising cross-intent interactions: tasks created through one
/// intent are discoverable through another. Adapted from V1's E2E suite.
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

    private func makeFindFilters(
        type: TaskType? = nil,
        project: ProjectEntity? = nil,
        status: TaskStatus? = nil
    ) -> FindTasksIntent.Filters {
        FindTasksIntent.Filters(
            type: type,
            project: project,
            status: status,
            completionDateFilter: nil,
            completionFromDate: nil,
            completionToDate: nil,
            lastStatusChangeDateFilter: nil,
            lastStatusChangeFromDate: nil,
            lastStatusChangeToDate: nil
        )
    }

    // MARK: - Cross-Intent E2E Flow

    @Test func addTaskThenFindViaBothIntents() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let entity = ProjectEntity.from(project)

        // Create task via visual AddTaskIntent
        let createResult = try await AddTaskIntent.execute(
            name: "E2E Test Task",
            taskDescription: "Created for end-to-end testing",
            type: .bug,
            project: entity,
            services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
        )

        // Retrieve via visual FindTasksIntent
        let findResults = try FindTasksIntent.execute(
            filters: makeFindFilters(type: .bug, project: entity),
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
            name: "Status Flow Task",
            taskDescription: nil,
            type: .feature,
            project: entity,
            services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
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
            filters: makeFindFilters(project: entity, status: .inProgress),
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

        // Find via visual FindTasksIntent
        let entity = ProjectEntity.from(project)
        let findResults = try FindTasksIntent.execute(
            filters: makeFindFilters(type: .chore, project: entity),
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
            name: "Bug in Alpha", taskDescription: nil, type: .bug, project: entityA,
            services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
        )
        _ = try await AddTaskIntent.execute(
            name: "Feature in Alpha", taskDescription: nil, type: .feature, project: entityA,
            services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
        )
        _ = try await AddTaskIntent.execute(
            name: "Bug in Beta", taskDescription: nil, type: .bug, project: entityB,
            services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
        )

        // Filter by type AND project
        let bugsInAlpha = try FindTasksIntent.execute(
            filters: makeFindFilters(type: .bug, project: entityA), modelContext: svc.context
        )
        #expect(bugsInAlpha.count == 1)
        #expect(bugsInAlpha.first?.name == "Bug in Alpha")

        // Filter by project only
        let alphaResults = try FindTasksIntent.execute(
            filters: makeFindFilters(project: entityA), modelContext: svc.context
        )
        #expect(alphaResults.count == 2)

        // Filter by type AND project B
        let bugsInBeta = try FindTasksIntent.execute(
            filters: makeFindFilters(type: .bug, project: entityB), modelContext: svc.context
        )
        #expect(bugsInBeta.count == 1)
        #expect(bugsInBeta.first?.name == "Bug in Beta")
    }

    // MARK: - Error Handling E2E

    @Test func addTaskWithNoProjectsThrowsNoProjects() async throws {
        let svc = try makeServices()
        let fakeEntity = ProjectEntity(id: UUID().uuidString, projectId: UUID(), name: "Ghost")

        await #expect(throws: VisualIntentError.self) {
            try await AddTaskIntent.execute(
                name: "Orphan", taskDescription: nil, type: .feature, project: fakeEntity,
                services: AddTaskIntent.Services(taskService: svc.task, projectService: svc.project)
            )
        }
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
}
