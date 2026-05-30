import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1192: a present-but-non-string `description` field on
/// the create intents (`CreateTaskIntent`, `CreateMilestoneIntent`) must be
/// rejected with an INVALID_INPUT error rather than silently dropped.
/// Previously `json["description"] as? String` returned nil for numbers,
/// booleans, arrays, etc., and the object was created without the description,
/// making a malformed request look successful.
@MainActor @Suite(.serialized)
struct IntentNonStringDescriptionTests {

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

    @Test func createTaskRejectsNumericDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"Task","type":"feature","description":123}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("description") == true)

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when description validation fails")
    }

    @Test func createTaskRejectsBooleanDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"Task","type":"feature","description":false}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("description") == true)

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when description validation fails")
    }

    @Test func createTaskRejectsArrayDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"Task","type":"feature","description":["x"]}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("description") == true)

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when description validation fails")
    }

    @Test func createTaskRejectsNullDescription() async throws {
        // An explicit JSON null is a present key with a non-string value and must
        // be rejected, not treated as "absent".
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"Task","type":"feature","description":null}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("description") == true)

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when description validation fails")
    }

    @Test func createTaskAcceptsStringDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"Task","type":"feature","description":"A description"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] is String)
        let task = try #require(try svc.context.fetch(FetchDescriptor<TransitTask>()).first)
        #expect(task.taskDescription == "A description")
    }

    @Test func createTaskAcceptsAbsentDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"Task","type":"feature"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] is String)
    }

    // MARK: - CreateMilestoneIntent

    @Test func createMilestoneRejectsNumericDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"v1.0","projectId":"\(project.id.uuidString)","description":123}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("description") == true)

        let milestones = try svc.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.isEmpty, "Milestone must not be created when description validation fails")
    }

    @Test func createMilestoneRejectsBooleanDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"v1.0","projectId":"\(project.id.uuidString)","description":true}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("description") == true)

        let milestones = try svc.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.isEmpty, "Milestone must not be created when description validation fails")
    }

    @Test func createMilestoneRejectsArrayDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"v1.0","projectId":"\(project.id.uuidString)","description":["x"]}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("description") == true)

        let milestones = try svc.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.isEmpty, "Milestone must not be created when description validation fails")
    }

    @Test func createMilestoneRejectsNullDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"v1.0","projectId":"\(project.id.uuidString)","description":null}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("description") == true)

        let milestones = try svc.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.isEmpty, "Milestone must not be created when description validation fails")
    }

    @Test func createMilestoneAcceptsStringDescription() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"v1.0","projectId":"\(project.id.uuidString)","description":"Beta release"}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["milestoneId"] is String)
        let milestone = try #require(try svc.context.fetch(FetchDescriptor<Milestone>()).first)
        #expect(milestone.milestoneDescription == "Beta release")
    }
}
