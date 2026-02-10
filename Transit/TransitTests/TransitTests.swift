import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct TransitTests {
    @Test
    func createIntentTaskAppearsInDashboardColumns() async throws {
        let fixture = try makeIntegrationFixture()

        let output = await CreateTaskIntent.execute(
            input: """
            {"projectId":"\(fixture.alpha.id.uuidString)","name":"Intent task","type":"feature"}
            """,
            taskService: fixture.taskService,
            projectService: fixture.projectService
        )

        let createdTaskID = try taskID(from: output)
        let tasks = try fixture.context.fetch(FetchDescriptor<TransitTask>())
        let columns = DashboardLogic.filteredColumns(tasks: tasks, selectedProjectIDs: [], now: .now)
        let ideaTasks = columns[.idea] ?? []

        #expect(ideaTasks.contains(where: { $0.id.uuidString.lowercased() == createdTaskID }))
    }

    @Test
    func updateStatusIntentIsReflectedInDashboardColumns() async throws {
        let fixture = try makeIntegrationFixture()

        let createOutput = await CreateTaskIntent.execute(
            input: """
            {"projectId":"\(fixture.alpha.id.uuidString)","name":"Promote me","type":"feature"}
            """,
            taskService: fixture.taskService,
            projectService: fixture.projectService
        )
        let displayID = try displayID(from: createOutput)

        _ = UpdateStatusIntent.execute(
            input: #"{"displayId":\#(displayID),"status":"in-progress"}"#,
            taskService: fixture.taskService
        )

        let tasks = try fixture.context.fetch(FetchDescriptor<TransitTask>())
        let columns = DashboardLogic.filteredColumns(tasks: tasks, selectedProjectIDs: [], now: .now)
        let activeTasks = columns[.inProgress] ?? []
        #expect(activeTasks.contains(where: { $0.name == "Promote me" }))
    }

    @Test
    func queryIntentReturnsStatusFilteredResults() async throws {
        let fixture = try makeIntegrationFixture()

        _ = await CreateTaskIntent.execute(
            input: """
            {"projectId":"\(fixture.alpha.id.uuidString)","name":"Alpha active","type":"bug"}
            """,
            taskService: fixture.taskService,
            projectService: fixture.projectService
        )
        _ = await CreateTaskIntent.execute(
            input: """
            {"projectId":"\(fixture.beta.id.uuidString)","name":"Beta idea","type":"chore"}
            """,
            taskService: fixture.taskService,
            projectService: fixture.projectService
        )

        let tasks = try fixture.context.fetch(FetchDescriptor<TransitTask>())
        guard let alphaActive = tasks.first(where: { $0.name == "Alpha active" }) else {
            Issue.record("Expected Alpha active task to be created")
            return
        }
        try fixture.taskService.updateStatus(task: alphaActive, to: .inProgress)

        let output = QueryTasksIntent.execute(
            input: #"{"status":"in-progress","project":"Alpha"}"#,
            taskService: fixture.taskService,
            projectService: fixture.projectService
        )

        let results = try tasksArray(from: output)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Alpha active")
        #expect(results.first?["status"] as? String == "in-progress")
    }

    @Test
    func createIntentAllocatesSequentialDisplayIDs() async throws {
        let fixture = try makeIntegrationFixture()

        let first = await CreateTaskIntent.execute(
            input: """
            {"projectId":"\(fixture.alpha.id.uuidString)","name":"First","type":"feature"}
            """,
            taskService: fixture.taskService,
            projectService: fixture.projectService
        )
        let second = await CreateTaskIntent.execute(
            input: """
            {"projectId":"\(fixture.alpha.id.uuidString)","name":"Second","type":"feature"}
            """,
            taskService: fixture.taskService,
            projectService: fixture.projectService
        )

        #expect(try displayID(from: first) == 1)
        #expect(try displayID(from: second) == 2)
    }
}

@MainActor
private func makeIntegrationFixture() throws -> (
    context: ModelContext,
    alpha: Project,
    beta: Project,
    taskService: TaskService,
    projectService: ProjectService
) {
    let container = try makeInMemoryModelContainer()
    let context = ModelContext(container)
    let projectService = ProjectService(modelContext: context)
    let alpha = try projectService.createProject(name: "Alpha", description: "Core", color: .blue)
    let beta = try projectService.createProject(name: "Beta", description: "Secondary", color: .green)
    let taskService = TaskService(
        modelContext: context,
        displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 1))
    )
    return (context, alpha, beta, taskService, projectService)
}

private func taskID(from json: String) throws -> String {
    let object = try parseObject(from: json)
    return try #require(object["taskId"] as? String)
}

private func displayID(from json: String) throws -> Int {
    let object = try parseObject(from: json)
    return try #require(object["displayId"] as? Int)
}

private func tasksArray(from json: String) throws -> [[String: Any]] {
    let object = try parseObject(from: json)
    #expect(object["ok"] as? Bool == true)
    return try #require(object["tasks"] as? [[String: Any]])
}

private func parseObject(from json: String) throws -> [String: Any] {
    let data = try #require(json.data(using: .utf8))
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}
