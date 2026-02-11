import Foundation
import SwiftData
import Testing
@testable import Transit

/// Integration tests for query intent filtering and display ID counter incrementing.
@MainActor @Suite(.serialized)
struct QueryAndDisplayIDIntegrationTests {

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
        let projectName = name ?? "QADI-\(UUID().uuidString.prefix(8))"
        let project = Project(name: projectName, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func tasksForProject(_ project: Project, in context: ModelContext) throws -> [TransitTask] {
        try context.fetch(FetchDescriptor<TransitTask>()).filter { $0.project?.id == project.id }
    }

    // MARK: - Query Returns Filtered Results

    @Test func queryWithStatusFilterReturnsMatchingTasks() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input1 = """
        {"projectId":"\(project.id.uuidString)","name":"Task A","type":"feature"}
        """
        let input2 = """
        {"projectId":"\(project.id.uuidString)","name":"Task B","type":"bug"}
        """
        let result1 = await CreateTaskIntent.execute(
            input: input1, taskService: svc.task, projectService: svc.project
        )
        _ = await CreateTaskIntent.execute(
            input: input2, taskService: svc.task, projectService: svc.project
        )

        // Move Task A to planning using taskId (avoids displayId collisions in shared store)
        let parsed1 = try parseJSON(result1)
        let taskId = try #require(parsed1["taskId"] as? String)
        let updateInput = """
        {"taskId":"\(taskId)","status":"planning"}
        """
        _ = UpdateStatusIntent.execute(input: updateInput, taskService: svc.task)

        // Query for idea tasks scoped to this project
        let queryResult = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\",\"status\":\"idea\"}",
            projectService: svc.project,
            modelContext: svc.context
        )
        let queryParsed = try parseJSONArray(queryResult)
        #expect(queryParsed.count == 1)
        #expect(queryParsed[0]["name"] as? String == "Task B")
    }

    @Test func queryWithNoFiltersReturnsAllTasks() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        _ = await CreateTaskIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\",\"name\":\"Task 1\",\"type\":\"feature\"}",
            taskService: svc.task, projectService: svc.project
        )
        _ = await CreateTaskIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\",\"name\":\"Task 2\",\"type\":\"bug\"}",
            taskService: svc.task, projectService: svc.project
        )

        let queryResult = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\"}",
            projectService: svc.project, modelContext: svc.context
        )
        let queryParsed = try parseJSONArray(queryResult)
        #expect(queryParsed.count == 2)
    }

    @Test func queryWithProjectFilterReturnsOnlyProjectTasks() async throws {
        let svc = try makeServices()
        let projectA = makeProject(in: svc.context, name: "Project A")
        let projectB = makeProject(in: svc.context, name: "Project B")

        _ = await CreateTaskIntent.execute(
            input: "{\"projectId\":\"\(projectA.id.uuidString)\",\"name\":\"A Task\",\"type\":\"feature\"}",
            taskService: svc.task, projectService: svc.project
        )
        _ = await CreateTaskIntent.execute(
            input: "{\"projectId\":\"\(projectB.id.uuidString)\",\"name\":\"B Task\",\"type\":\"feature\"}",
            taskService: svc.task, projectService: svc.project
        )

        let queryResult = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(projectA.id.uuidString)\"}",
            projectService: svc.project,
            modelContext: svc.context
        )
        let queryParsed = try parseJSONArray(queryResult)
        #expect(queryParsed.count == 1)
        #expect(queryParsed[0]["name"] as? String == "A Task")
    }

    // MARK: - Display ID Counter Increments Across Creates

    @Test func displayIdIncrementsAcrossMultipleCreates() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        var displayIds: [Int] = []
        for index in 1...3 {
            let input = """
            {"projectId":"\(project.id.uuidString)","name":"Task \(index)","type":"feature"}
            """
            let result = await CreateTaskIntent.execute(
                input: input, taskService: svc.task, projectService: svc.project
            )
            let parsed = try parseJSON(result)
            if let displayId = parsed["displayId"] as? Int {
                displayIds.append(displayId)
            }
        }

        let tasks = try tasksForProject(project, in: svc.context)
        #expect(tasks.count == 3)

        // If we got permanent IDs, verify they're unique and incrementing
        if !displayIds.isEmpty {
            #expect(Set(displayIds).count == displayIds.count)
            for idx in 1..<displayIds.count {
                #expect(displayIds[idx] > displayIds[idx - 1])
            }
        }
    }

    @Test func queryResponseIncludesCorrectFields() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        _ = await CreateTaskIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\",\"name\":\"Check Fields\",\"type\":\"research\"}",
            taskService: svc.task, projectService: svc.project
        )

        let queryResult = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\"}",
            projectService: svc.project, modelContext: svc.context
        )
        let queryParsed = try parseJSONArray(queryResult)
        #expect(queryParsed.count == 1)

        let taskDict = queryParsed[0]
        #expect(taskDict["taskId"] is String)
        #expect(taskDict["name"] as? String == "Check Fields")
        #expect(taskDict["status"] as? String == "idea")
        #expect(taskDict["type"] as? String == "research")
        #expect(taskDict["projectId"] is String)
        #expect(taskDict["projectName"] as? String == project.name)
        #expect(taskDict["lastStatusChangeDate"] is String)
    }
}
