import Foundation
import SwiftData
import Testing
@testable import Transit

/// QueryTasksIntent must reject filters whose value is an explicit JSON `null`, not treat them like an omitted key.
@MainActor @Suite(.serialized)
struct QueryTasksIntentNullFilterTests {

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let project: ProjectService
        let milestone: MilestoneService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: allocator),
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
        displayId: Int
    ) -> TransitTask {
        let task = TransitTask(name: name, type: .feature, project: project, displayID: .permanent(displayId))
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        return task
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeSeededServices() throws -> Services {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        // Seed a few tasks so a "silently ignored null" bug would return a non-empty array.
        makeTask(in: svc.context, project: project, name: "Task A", displayId: 1)
        makeTask(in: svc.context, project: project, name: "Task B", displayId: 2)
        return svc
    }

    private func expectInvalidInput(_ input: String) throws {
        let svc = try makeSeededServices()
        let result = QueryTasksIntent.execute(
            input: input, projectService: svc.project, taskService: svc.task,
            milestoneService: svc.milestone
        )
        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT", "input \(input) should be rejected")
    }

    // MARK: - Explicit Null Rejection

    /// The most serious case: a null displayId must not fall through to fetchAllTasks().
    @Test func nullDisplayIdIsRejected() throws {
        try expectInvalidInput("{\"displayId\":null}")
    }

    @Test func nullProjectIdIsRejected() throws {
        try expectInvalidInput("{\"projectId\":null}")
    }

    @Test func nullStatusIsRejected() throws {
        try expectInvalidInput("{\"status\":null}")
    }

    @Test func nullTypeIsRejected() throws {
        try expectInvalidInput("{\"type\":null}")
    }

    @Test func nullSearchIsRejected() throws {
        try expectInvalidInput("{\"search\":null}")
    }

    @Test func nullCompletionDateIsRejected() throws {
        try expectInvalidInput("{\"completionDate\":null}")
    }

    @Test func nullLastStatusChangeDateIsRejected() throws {
        try expectInvalidInput("{\"lastStatusChangeDate\":null}")
    }

    @Test func nullMilestoneIsRejected() throws {
        try expectInvalidInput("{\"milestone\":null}")
    }

    @Test func nullMilestoneDisplayIdIsRejected() throws {
        try expectInvalidInput("{\"milestoneDisplayId\":null}")
    }

    // MARK: - Valid Inputs Still Work (no regression)

    /// An omitted key (no explicit null) must keep working as "return all tasks".
    @Test func omittedKeysStillReturnAllTasks() throws {
        let svc = try makeSeededServices()
        let result = QueryTasksIntent.execute(
            input: "{}", projectService: svc.project, taskService: svc.task,
            milestoneService: svc.milestone
        )
        let data = try #require(result.data(using: .utf8))
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(parsed.count == 2)
    }

    /// A present, valid displayId must still perform the single-task lookup.
    @Test func validDisplayIdStillLooksUpSingleTask() throws {
        let svc = try makeSeededServices()
        let result = QueryTasksIntent.execute(
            input: "{\"displayId\":1}", projectService: svc.project, taskService: svc.task,
            milestoneService: svc.milestone
        )
        let data = try #require(result.data(using: .utf8))
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(parsed.count == 1)
        #expect(parsed.first?["displayId"] as? Int == 1)
    }
}
