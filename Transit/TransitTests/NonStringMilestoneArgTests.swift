import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1114: a present-but-non-string `milestone` argument must
/// be rejected with an input validation error instead of being silently treated as
/// absent. Previously `args["milestone"] as? String` returned nil for numbers,
/// booleans, arrays, etc., causing the operation to succeed without assigning the
/// requested milestone.
@MainActor @Suite(.serialized)
struct NonStringMilestoneArgTests {

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let milestone: MilestoneService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let taskAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: taskAllocator),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator),
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
    private func makeMilestone(
        in context: ModelContext,
        name: String,
        project: Project,
        displayId: Int
    ) -> Milestone {
        let milestone = Milestone(name: name, description: nil, project: project, displayID: .permanent(displayId))
        context.insert(milestone)
        return milestone
    }

    private func makeTask(
        in context: ModelContext,
        name: String,
        project: Project,
        milestone: Milestone? = nil,
        displayId: Int
    ) -> TransitTask {
        let task = TransitTask(
            name: name, type: .feature, project: project, displayID: .permanent(displayId)
        )
        StatusEngine.initializeNewTask(task)
        task.milestone = milestone
        context.insert(task)
        return task
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - CreateTaskIntent

    /// T-1114: A numeric `milestone` value must be rejected with INVALID_INPUT,
    /// not silently dropped. The task must not be created when validation fails.
    @Test func createTaskIntentRejectsNumericMilestone() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"name":"Task","type":"feature","project":"\(project.name)","milestone":42}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestone must be a string") == true)

        // Task must not have been created
        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when milestone validation fails")
    }

    /// T-1114: A boolean `milestone` value must be rejected.
    @Test func createTaskIntentRejectsBooleanMilestone() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"Task","type":"feature","project":"\(project.name)","milestone":true}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestone must be a string") == true)

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when milestone validation fails")
    }

    /// T-1114: A null `milestone` value must be rejected.
    @Test func createTaskIntentRejectsNullMilestone() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"Task","type":"feature","project":"\(project.name)","milestone":null}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestone must be a string") == true)

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when milestone validation fails")
    }

    /// T-1114: An array `milestone` value must be rejected.
    @Test func createTaskIntentRejectsArrayMilestone() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"Task","type":"feature","project":"\(project.name)","milestone":["v1.0"]}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestone must be a string") == true)

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when milestone validation fails")
    }

    // MARK: - UpdateTaskIntent (via IntentHelpers.assignMilestone)

    /// T-1114: A numeric `milestone` value on update must be rejected with INVALID_INPUT
    /// and must not clear the existing milestone assignment.
    @Test func updateTaskIntentRejectsNumericMilestone() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(
            in: svc.context, name: "Task", project: project, milestone: milestone, displayId: 10
        )

        let input = """
        {"displayId":10,"milestone":42}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestone must be a string") == true)
        #expect(task.milestone?.id == milestone.id, "Existing milestone must remain assigned")
    }

    /// T-1114: A boolean `milestone` value on update must be rejected.
    @Test func updateTaskIntentRejectsBooleanMilestone() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(
            in: svc.context, name: "Task", project: project, milestone: milestone, displayId: 10
        )

        let input = """
        {"displayId":10,"milestone":true}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestone must be a string") == true)
        #expect(task.milestone?.id == milestone.id, "Existing milestone must remain assigned")
    }

    // MARK: - IntentHelpers.assignMilestone (direct)

    @Test func assignMilestoneRejectsNumericMilestone() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = try await svc.task.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let json: [String: Any] = ["milestone": 42]
        let error = IntentHelpers.assignMilestone(
            from: json, to: task, milestoneService: svc.milestone
        )

        let errorString = try #require(error)
        let parsed = try parseJSON(errorString)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestone must be a string") == true)
    }

    @Test func assignMilestoneRejectsDictionaryMilestone() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let task = try await svc.task.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let json: [String: Any] = ["milestone": ["name": "v1.0"]]
        let error = IntentHelpers.assignMilestone(
            from: json, to: task, milestoneService: svc.milestone
        )

        let errorString = try #require(error)
        let parsed = try parseJSON(errorString)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestone must be a string") == true)
    }
}
