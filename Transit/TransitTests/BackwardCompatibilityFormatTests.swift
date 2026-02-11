import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Verifies existing intent names and JSON response formats remain unchanged. [Task 15.4, 15.5]
@MainActor @Suite(.serialized)
struct BackwardCompatibilityFormatTests {

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
    private func makeProject(
        in context: ModelContext,
        name: String = "Test Project"
    ) -> Project {
        let project = Project(
            name: name, description: "A test project",
            gitRepo: nil, colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeTask(
        in context: ModelContext,
        project: Project,
        name: String = "Task",
        type: TaskType = .feature,
        displayId: Int,
        status: TaskStatus = .idea
    ) -> TransitTask {
        let task = TransitTask(
            name: name, type: type, project: project,
            displayID: .permanent(displayId)
        )
        StatusEngine.initializeNewTask(task)
        if status != .idea {
            StatusEngine.applyTransition(task: task, to: status)
        }
        context.insert(task)
        return task
    }

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        )
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    // MARK: - 15.4: Existing Intent Names Unchanged

    @Test func createTaskIntentTitleUnchanged() {
        #expect(String(localized: CreateTaskIntent.title) == "Transit: Create Task")
    }

    @Test func updateStatusIntentTitleUnchanged() {
        #expect(String(localized: UpdateStatusIntent.title) == "Transit: Update Status")
    }

    @Test func queryTasksIntentTitleUnchanged() {
        #expect(String(localized: QueryTasksIntent.title) == "Transit: Query Tasks")
    }

    // MARK: - 15.5: JSON Input/Output Formats Unchanged

    @Test func queryTasksResponseFieldsUnchanged() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "BCFmtFields")
        let task = makeTask(
            in: svc.context, project: project,
            displayId: 5, status: .done
        )
        task.completionDate = Date()

        let result = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\"}",
            projectService: svc.project, modelContext: svc.context
        )
        let parsed = try parseJSONArray(result)
        let item = try #require(parsed.first)

        #expect(item["taskId"] is String)
        #expect(item["displayId"] is Int)
        #expect(item["name"] is String)
        #expect(item["status"] is String)
        #expect(item["type"] is String)
        #expect(item["projectId"] is String)
        #expect(item["projectName"] is String)
        #expect(item["lastStatusChangeDate"] is String)
        #expect(item["completionDate"] is String)
    }

    @Test func createTaskResponseFieldsUnchanged() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"Format Check","type":"feature"}
        """
        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )
        let parsed = try parseJSON(result)

        #expect(parsed["taskId"] is String)
        #expect(parsed["status"] as? String == "idea")
        #expect(parsed.keys.contains("displayId"))
    }

    @Test func updateStatusResponseFieldsUnchanged() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(
            in: svc.context, project: project, displayId: 77707
        )

        let result = UpdateStatusIntent.execute(
            input: "{\"taskId\":\"\(task.id.uuidString)\",\"status\":\"spec\"}",
            taskService: svc.task
        )
        let parsed = try parseJSON(result)

        #expect(parsed["taskId"] is String)
        #expect(parsed["displayId"] is Int)
        #expect(parsed["previousStatus"] is String)
        #expect(parsed["status"] is String)
    }

    @Test func errorResponseFormatUnchanged() throws {
        let svc = try makeServices()
        let result = QueryTasksIntent.execute(
            input: "bad json",
            projectService: svc.project,
            modelContext: svc.context
        )
        let parsed = try parseJSON(result)

        #expect(parsed["error"] is String)
        #expect(parsed["hint"] is String)
    }

    @Test func queryTasksAcceptsAllExistingFilterFormats() throws {
        let svc = try makeServices()
        let project = makeProject(
            in: svc.context, name: "BCFmtFilters"
        )
        makeTask(
            in: svc.context, project: project,
            name: "BCFilterTask", type: .bug, displayId: 1, status: .idea
        )

        let statusFilter = QueryTasksIntent.execute(
            input: "{\"status\":\"idea\",\"projectId\":\"\(project.id.uuidString)\"}",
            projectService: svc.project, modelContext: svc.context
        )
        #expect(try parseJSONArray(statusFilter).count == 1)

        let typeFilter = QueryTasksIntent.execute(
            input: "{\"type\":\"bug\",\"projectId\":\"\(project.id.uuidString)\"}",
            projectService: svc.project, modelContext: svc.context
        )
        #expect(try parseJSONArray(typeFilter).count == 1)

        let projectFilter = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\"}",
            projectService: svc.project, modelContext: svc.context
        )
        #expect(try parseJSONArray(projectFilter).count == 1)

        let emptyFilter = QueryTasksIntent.execute(
            input: "{}", projectService: svc.project, modelContext: svc.context
        )
        #expect(
            try parseJSONArray(emptyFilter)
                .contains { $0["name"] as? String == "BCFilterTask" }
        )

        let emptyString = QueryTasksIntent.execute(
            input: "", projectService: svc.project, modelContext: svc.context
        )
        #expect(
            try parseJSONArray(emptyString)
                .contains { $0["name"] as? String == "BCFilterTask" }
        )
    }
}
