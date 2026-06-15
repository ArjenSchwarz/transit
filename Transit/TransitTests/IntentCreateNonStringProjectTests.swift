import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1453: a present-but-non-string `project` field on the
/// create intents (`CreateTaskIntent`, `CreateMilestoneIntent`) must be rejected
/// with an INVALID_INPUT `project must be a string` error rather than silently
/// dropped. Previously `json["project"] as? String` returned nil for numbers,
/// booleans, arrays, etc., and — when no `projectId` was supplied — the request
/// fell through to the generic missing-project error instead of surfacing the
/// type mismatch. Mirrors the T-1116 pattern already enforced on the query
/// intents. projectId-takes-precedence is preserved: a valid projectId wins and
/// the malformed `project` value is ignored.
@MainActor @Suite(.serialized)
struct IntentCreateNonStringProjectTests {

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let milestone: MilestoneService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: allocator),
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

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - CreateTaskIntent

    @Test func createTaskRejectsNumericProject() async throws {
        let svc = try makeServices()
        _ = makeProject(in: svc.context, name: "Alpha")

        let input = """
        {"name":"Task","type":"bug","project":123}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("project") == true)
        #expect((parsed["hint"] as? String)?.contains("string") == true)

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when project validation fails")
    }

    @Test func createTaskRejectsBooleanProject() async throws {
        let svc = try makeServices()
        _ = makeProject(in: svc.context, name: "Alpha")

        let input = """
        {"name":"Task","type":"bug","project":true}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("project") == true)
    }

    @Test func createTaskRejectsArrayProject() async throws {
        let svc = try makeServices()
        _ = makeProject(in: svc.context, name: "Alpha")

        let input = """
        {"name":"Task","type":"bug","project":["Alpha"]}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("project") == true)
    }

    @Test func createTaskValidProjectIdIgnoresNonStringProjectName() async throws {
        // projectId-takes-precedence: a valid projectId must win even when the
        // `project` name is malformed. Guards against an over-strict fix.
        let svc = try makeServices()
        let target = makeProject(in: svc.context, name: "Target")

        let input = """
        {"name":"Task","type":"bug","projectId":"\(target.id.uuidString)","project":123}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] is String)
        let task = try #require(try svc.context.fetch(FetchDescriptor<TransitTask>()).first)
        #expect(task.project?.id == target.id)
    }

    // MARK: - CreateMilestoneIntent

    @Test func createMilestoneRejectsNumericProject() async throws {
        let svc = try makeServices()
        _ = makeProject(in: svc.context, name: "Alpha")

        let input = """
        {"name":"v1.0","project":123}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("project") == true)
        #expect((parsed["hint"] as? String)?.contains("string") == true)

        let milestones = try svc.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.isEmpty, "Milestone must not be created when project validation fails")
    }

    @Test func createMilestoneRejectsBooleanProject() async throws {
        let svc = try makeServices()
        _ = makeProject(in: svc.context, name: "Alpha")

        let input = """
        {"name":"v1.0","project":false}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("project") == true)
    }

    @Test func createMilestoneRejectsArrayProject() async throws {
        let svc = try makeServices()
        _ = makeProject(in: svc.context, name: "Alpha")

        let input = """
        {"name":"v1.0","project":["Alpha"]}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("project") == true)
    }

    @Test func createMilestoneValidProjectIdIgnoresNonStringProjectName() async throws {
        let svc = try makeServices()
        let target = makeProject(in: svc.context, name: "Target")

        let input = """
        {"name":"v1.0","projectId":"\(target.id.uuidString)","project":123}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["milestoneId"] is String)
        #expect(parsed["projectId"] as? String == target.id.uuidString)
    }
}
