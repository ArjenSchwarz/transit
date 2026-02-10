import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct QueryTasksIntentTests {
    @Test
    func noFiltersReturnsAllTasks() async throws {
        let fixture = try await makeQueryFixture()
        let output = QueryTasksIntent.execute(
            input: "{}",
            taskService: fixture.taskService,
            projectService: fixture.projectService
        )
        let tasks = try taskArray(from: output)
        #expect(tasks.count == 3)
    }

    @Test
    func statusFilterReturnsMatchingTasks() async throws {
        let fixture = try await makeQueryFixture()
        let output = QueryTasksIntent.execute(
            input: #"{"status":"in-progress"}"#,
            taskService: fixture.taskService,
            projectService: fixture.projectService
        )
        let tasks = try taskArray(from: output)
        #expect(tasks.count == 1)
        #expect(tasks.first?["status"] as? String == "in-progress")
    }

    @Test
    func projectFilterByNameReturnsOnlyProjectTasks() async throws {
        let fixture = try await makeQueryFixture()
        let output = QueryTasksIntent.execute(
            input: #"{"project":"Beta"}"#,
            taskService: fixture.taskService,
            projectService: fixture.projectService
        )
        let tasks = try taskArray(from: output)
        #expect(tasks.count == 1)
        #expect(tasks.first?["name"] as? String == "Beta task")
    }

    @Test
    func unknownProjectReturnsProjectNotFound() async throws {
        let fixture = try await makeQueryFixture()
        let output = QueryTasksIntent.execute(
            input: #"{"project":"DoesNotExist"}"#,
            taskService: fixture.taskService,
            projectService: fixture.projectService
        )
        #expect(try errorCode(from: output) == "PROJECT_NOT_FOUND")
    }
}

@MainActor
private func makeQueryFixture() async throws -> (taskService: TaskService, projectService: ProjectService) {
    let container = try makeInMemoryModelContainer()
    let context = ModelContext(container)
    let projectService = ProjectService(modelContext: context)
    let alpha = try projectService.createProject(name: "Alpha", description: "One", color: .blue)
    let beta = try projectService.createProject(name: "Beta", description: "Two", color: .green)

    let taskService = TaskService(
        modelContext: context,
        displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 100))
    )

    let idea = try await taskService.createTask(project: alpha, name: "Alpha idea", type: .feature)
    let inProgress = try await taskService.createTask(project: alpha, name: "Alpha active", type: .bug)
    try taskService.updateStatus(task: inProgress, to: .inProgress)
    _ = try await taskService.createTask(project: beta, name: "Beta task", type: .chore)
    idea.lastStatusChangeDate = Date(timeIntervalSince1970: 10)
    inProgress.lastStatusChangeDate = Date(timeIntervalSince1970: 20)
    try context.save()

    return (taskService, projectService)
}

private func taskArray(from json: String) throws -> [[String: Any]] {
    let object = try parseJSONObject(json)
    #expect(object["ok"] as? Bool == true)
    return try #require(object["tasks"] as? [[String: Any]])
}

private func errorCode(from json: String) throws -> String {
    let object = try parseJSONObject(json)
    let error = try #require(object["error"] as? [String: Any])
    return try #require(error["code"] as? String)
}

private func parseJSONObject(_ json: String) throws -> [String: Any] {
    let data = try #require(json.data(using: .utf8))
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}
