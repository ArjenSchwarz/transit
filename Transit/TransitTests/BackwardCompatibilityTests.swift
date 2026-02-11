import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Verifies that existing JSON-based intents remain unchanged after adding
/// Shortcuts-friendly visual intents. Adapted from V1's comprehensive test suite.
@MainActor @Suite(.serialized)
struct BackwardCompatibilityTests {

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

    @discardableResult
    private func makeTask(
        in context: ModelContext,
        project: Project,
        name: String = "Task",
        type: TaskType = .feature,
        displayId: Int,
        status: TaskStatus = .idea
    ) -> TransitTask {
        let task = TransitTask(name: name, type: type, project: project, displayID: .permanent(displayId))
        StatusEngine.initializeNewTask(task)
        if status != .idea {
            StatusEngine.applyTransition(task: task, to: status)
        }
        context.insert(task)
        return task
    }

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - QueryTasksIntent Without Date Filters

    @Test func queryWithEmptyStringReturnsResults() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "BCEmptyStr")
        makeTask(in: svc.context, project: project, name: "A", displayId: 1)
        makeTask(in: svc.context, project: project, name: "B", displayId: 2)

        let result = QueryTasksIntent.execute(
            input: "", projectService: svc.project, modelContext: svc.context
        )
        let parsed = try parseJSONArray(result)
        #expect(parsed.count >= 2)
        #expect(parsed.contains { $0["name"] as? String == "A" })
        #expect(parsed.contains { $0["name"] as? String == "B" })
    }

    @Test func queryWithEmptyObjectReturnsResults() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "BCEmptyObj")
        makeTask(in: svc.context, project: project, name: "BCTask", displayId: 1)

        let result = QueryTasksIntent.execute(
            input: "{}", projectService: svc.project, modelContext: svc.context
        )
        let parsed = try parseJSONArray(result)
        #expect(parsed.contains { $0["name"] as? String == "BCTask" })
    }

    @Test func queryWithStatusFilterStillWorks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "BCStatus")
        makeTask(in: svc.context, project: project, name: "BCIdea", displayId: 1, status: .idea)
        makeTask(in: svc.context, project: project, name: "BCPlanning", displayId: 2, status: .planning)

        let result = QueryTasksIntent.execute(
            input: "{\"status\":\"planning\",\"projectId\":\"\(project.id.uuidString)\"}",
            projectService: svc.project, modelContext: svc.context
        )
        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["status"] as? String == "planning")
        #expect(parsed.first?["name"] as? String == "BCPlanning")
    }

    @Test func queryWithTypeFilterStillWorks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "BCType")
        makeTask(in: svc.context, project: project, name: "BCBug", type: .bug, displayId: 1)
        makeTask(in: svc.context, project: project, name: "BCFeature", type: .feature, displayId: 2)

        let result = QueryTasksIntent.execute(
            input: "{\"type\":\"bug\",\"projectId\":\"\(project.id.uuidString)\"}",
            projectService: svc.project, modelContext: svc.context
        )
        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["type"] as? String == "bug")
    }

    @Test func queryWithProjectIdFilterStillWorks() throws {
        let svc = try makeServices()
        let projectA = makeProject(in: svc.context, name: "BCA")
        let projectB = makeProject(in: svc.context, name: "BCB")
        makeTask(in: svc.context, project: projectA, name: "In A", displayId: 1)
        makeTask(in: svc.context, project: projectB, name: "In B", displayId: 2)

        let result = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(projectA.id.uuidString)\"}",
            projectService: svc.project, modelContext: svc.context
        )
        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "In A")
    }

    // MARK: - CreateTaskIntent With Current JSON Format

    @Test func createTaskWithProjectIdAndNameAndType() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"New Task","type":"feature"}
        """
        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )
        let parsed = try parseJSON(result)

        #expect(parsed["taskId"] is String)
        #expect(parsed["status"] as? String == "idea")
        #expect(parsed.keys.contains("displayId"))
    }

    @Test func createTaskWithProjectName() async throws {
        let svc = try makeServices()
        let uniqueName = "BCProjName-\(UUID().uuidString.prefix(8))"
        makeProject(in: svc.context, name: uniqueName)

        let input = """
        {"project":"\(uniqueName)","name":"Named Project Task","type":"bug"}
        """
        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )
        let parsed = try parseJSON(result)

        #expect(parsed["taskId"] is String)
        #expect(parsed["status"] as? String == "idea")
    }

    @Test func createTaskWithDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"Task","type":"chore","description":"A desc"}
        """
        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )
        let parsed = try parseJSON(result)

        #expect(parsed["status"] as? String == "idea")
    }

    @Test func createTaskWithMetadata() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"Meta Task","type":"feature","metadata":{"git.branch":"main"}}
        """
        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )
        let parsed = try parseJSON(result)

        #expect(parsed["taskId"] is String)
        #expect(parsed["status"] as? String == "idea")
    }

    @Test func createTaskErrorCodesUnchanged() async throws {
        let svc = try makeServices()

        // INVALID_INPUT for missing name
        let project = makeProject(in: svc.context)
        let noName = await CreateTaskIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\",\"type\":\"feature\"}",
            taskService: svc.task, projectService: svc.project
        )
        #expect(try parseJSON(noName)["error"] as? String == "INVALID_INPUT")

        // INVALID_TYPE for unknown type
        let badType = await CreateTaskIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\",\"name\":\"X\",\"type\":\"epic\"}",
            taskService: svc.task, projectService: svc.project
        )
        #expect(try parseJSON(badType)["error"] as? String == "INVALID_TYPE")

        // PROJECT_NOT_FOUND for unknown project name
        let noProject = await CreateTaskIntent.execute(
            input: "{\"project\":\"NonExistentProjectBC\",\"name\":\"X\",\"type\":\"feature\"}",
            taskService: svc.task, projectService: svc.project
        )
        #expect(try parseJSON(noProject)["error"] as? String == "PROJECT_NOT_FOUND")

        // INVALID_INPUT for malformed JSON
        let badJSON = await CreateTaskIntent.execute(
            input: "not json", taskService: svc.task, projectService: svc.project
        )
        #expect(try parseJSON(badJSON)["error"] as? String == "INVALID_INPUT")
    }

    // MARK: - UpdateStatusIntent Unchanged

    @Test func updateStatusViaTaskIdStillWorks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project, displayId: 10)

        let result = UpdateStatusIntent.execute(
            input: "{\"taskId\":\"\(task.id.uuidString)\",\"status\":\"planning\"}",
            taskService: svc.task
        )
        let parsed = try parseJSON(result)

        #expect(parsed["previousStatus"] as? String == "idea")
        #expect(parsed["status"] as? String == "planning")
    }

    @Test func updateStatusViaDisplayIdStillWorks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = makeTask(in: svc.context, project: project, displayId: 77742)

        let result = UpdateStatusIntent.execute(
            input: "{\"taskId\":\"\(task.id.uuidString)\",\"status\":\"planning\"}",
            taskService: svc.task
        )
        let parsed = try parseJSON(result)

        #expect(parsed["displayId"] as? Int == 77742)
        #expect(parsed["previousStatus"] as? String == "idea")
        #expect(parsed["status"] as? String == "planning")
        #expect(parsed["taskId"] is String)
    }

    @Test func updateStatusErrorCodesUnchanged() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 88801)

        // TASK_NOT_FOUND
        let notFound = UpdateStatusIntent.execute(
            input: "{\"displayId\":99988,\"status\":\"planning\"}",
            taskService: svc.task
        )
        #expect(try parseJSON(notFound)["error"] as? String == "TASK_NOT_FOUND")

        // INVALID_STATUS
        let badStatus = UpdateStatusIntent.execute(
            input: "{\"displayId\":88801,\"status\":\"flying\"}",
            taskService: svc.task
        )
        #expect(try parseJSON(badStatus)["error"] as? String == "INVALID_STATUS")

        // INVALID_INPUT for malformed JSON
        let badJSON = UpdateStatusIntent.execute(
            input: "not json", taskService: svc.task
        )
        #expect(try parseJSON(badJSON)["error"] as? String == "INVALID_INPUT")

        // INVALID_INPUT for missing both identifiers
        let noId = UpdateStatusIntent.execute(
            input: "{\"status\":\"planning\"}", taskService: svc.task
        )
        #expect(try parseJSON(noId)["error"] as? String == "INVALID_INPUT")
    }
}
