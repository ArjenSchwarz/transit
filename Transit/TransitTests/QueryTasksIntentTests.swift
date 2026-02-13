import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct QueryTasksIntentTests {

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
        status: TaskStatus = .idea,
        completionDate: Date? = nil,
        lastStatusChangeDate: Date? = nil
    ) -> TransitTask {
        let task = TransitTask(name: name, type: type, project: project, displayID: .permanent(displayId))
        StatusEngine.initializeNewTask(task)
        if status != .idea {
            StatusEngine.applyTransition(task: task, to: status)
        }
        if let completionDate {
            task.completionDate = completionDate
        }
        if let lastStatusChangeDate {
            task.lastStatusChangeDate = lastStatusChangeDate
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

    // MARK: - No Filters

    @Test func noFiltersReturnsAllTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Task A", displayId: 1)
        makeTask(in: svc.context, project: project, name: "Task B", displayId: 2)
        makeTask(in: svc.context, project: project, name: "Task C", displayId: 3)

        let result = QueryTasksIntent.execute(
            input: "{}", projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 3)
    }

    @Test func emptyInputReturnsAllTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Task A", displayId: 1)

        let result = QueryTasksIntent.execute(
            input: "", projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
    }

    // MARK: - Status Filter

    @Test func statusFilterReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Idea Task", displayId: 1, status: .idea)
        makeTask(in: svc.context, project: project, name: "Planning Task", displayId: 2, status: .planning)
        makeTask(in: svc.context, project: project, name: "Another Idea", displayId: 3, status: .idea)

        let result = QueryTasksIntent.execute(
            input: "{\"status\":\"idea\"}", projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 2)
        for item in parsed {
            #expect(item["status"] as? String == "idea")
        }
    }

    // MARK: - Project Filter

    @Test func projectFilterReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let projectA = makeProject(in: svc.context, name: "Project A")
        let projectB = makeProject(in: svc.context, name: "Project B")
        makeTask(in: svc.context, project: projectA, name: "A Task", displayId: 1)
        makeTask(in: svc.context, project: projectB, name: "B Task", displayId: 2)

        let result = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(projectA.id.uuidString)\"}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "A Task")
    }

    @Test func projectNotFoundForInvalidProjectId() throws {
        let svc = try makeServices()

        let fakeId = UUID().uuidString
        let result = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(fakeId)\"}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "PROJECT_NOT_FOUND")
    }

    // MARK: - Type Filter

    @Test func typeFilterReturnsMatchingTasks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, name: "Bug Task", type: .bug, displayId: 1)
        makeTask(in: svc.context, project: project, name: "Feature Task", type: .feature, displayId: 2)

        let result = QueryTasksIntent.execute(
            input: "{\"type\":\"bug\"}", projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["type"] as? String == "bug")
    }

    // MARK: - Response Format

    // MARK: - DisplayId Lookup

    @Test func displayIdLookupReturnsDetailedTask() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = TransitTask(
            name: "Detailed Task",
            description: "A task with details",
            type: .bug,
            project: project,
            displayID: .permanent(42),
            metadata: ["git.branch": "feature/test"]
        )
        StatusEngine.initializeNewTask(task)
        svc.context.insert(task)

        let result = QueryTasksIntent.execute(
            input: "{\"displayId\":42}", projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        let item = try #require(parsed.first)
        #expect(item["displayId"] as? Int == 42)
        #expect(item["name"] as? String == "Detailed Task")
        #expect(item["description"] as? String == "A task with details")
        let metadata = try #require(item["metadata"] as? [String: String])
        #expect(metadata["git.branch"] == "feature/test")
    }

    @Test func displayIdNotFoundReturnsEmptyArray() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 1)

        let result = QueryTasksIntent.execute(
            input: "{\"displayId\":999}", projectService: svc.project, modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.isEmpty)
    }

    @Test func displayIdWithNonMatchingFilterReturnsEmptyArray() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 10, status: .idea)

        let result = QueryTasksIntent.execute(
            input: "{\"displayId\":10,\"status\":\"done\"}",
            projectService: svc.project,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.isEmpty)
    }

    // MARK: - Response Format

    @Test func responseContainsAllRequiredFields() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, project: project, displayId: 5)

        let result = QueryTasksIntent.execute(
            input: "{}", projectService: svc.project, modelContext: svc.context
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
        #expect(item.keys.contains("lastStatusChangeDate"))
    }
}
