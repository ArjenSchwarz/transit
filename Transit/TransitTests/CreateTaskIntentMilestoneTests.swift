import Foundation
import SwiftData
import Testing
@testable import Transit

/// Milestone-related tests for CreateTaskIntent [req 13.6]
@MainActor @Suite(.serialized)
struct CreateTaskIntentMilestoneTests {

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let milestone: MilestoneService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let taskStore = InMemoryCounterStore()
        let taskAllocator = DisplayIDAllocator(store: taskStore)
        let milestoneStore = InMemoryCounterStore()
        let milestoneAllocator = DisplayIDAllocator(store: milestoneStore)
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

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Milestone Assignment at Creation

    @Test func createTaskWithMilestoneDisplayId() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"name":"Task","type":"feature","project":"\(project.name)","milestoneDisplayId":1}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] is String)
        let milestoneInfo = parsed["milestone"] as? [String: Any]
        #expect(milestoneInfo?["name"] as? String == "v1.0")
        #expect(milestoneInfo?["displayId"] as? Int == 1)
    }

    @Test func createTaskWithMilestoneName() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"name":"Task","type":"feature","project":"\(project.name)","milestone":"v1.0"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] is String)
        let milestoneInfo = parsed["milestone"] as? [String: Any]
        #expect(milestoneInfo?["name"] as? String == "v1.0")
    }

    @Test func createTaskWithUnknownMilestoneReturnsMilestoneNotFound() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"Task","type":"feature","project":"\(project.name)","milestoneDisplayId":999}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "MILESTONE_NOT_FOUND")
    }

    // Regression test for T-260: milestone failure must not leave an orphaned task
    @Test func createTaskWithUnknownMilestoneDoesNotPersistTask() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"Orphan Check","type":"bug","project":"\(project.name)","milestoneDisplayId":999}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "MILESTONE_NOT_FOUND")

        // Verify no task was persisted
        let descriptor = FetchDescriptor<TransitTask>()
        let tasks = try svc.context.fetch(descriptor)
        #expect(tasks.isEmpty, "Task should not be created when milestone lookup fails")
    }

    @Test func createTaskWithUnknownMilestoneNameDoesNotPersistTask() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"Orphan Check","type":"bug","project":"\(project.name)","milestone":"nonexistent"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "MILESTONE_NOT_FOUND")

        let descriptor = FetchDescriptor<TransitTask>()
        let tasks = try svc.context.fetch(descriptor)
        #expect(tasks.isEmpty, "Task should not be created when milestone name lookup fails")
    }

    // Regression test for T-260: project mismatch must not leave an orphaned task
    @Test func createTaskWithMilestoneInDifferentProjectDoesNotPersistTask() async throws {
        let svc = try makeServices()
        let projectA = makeProject(in: svc.context, name: "Project A")
        let projectB = makeProject(in: svc.context, name: "Project B")
        makeMilestone(in: svc.context, name: "v1.0", project: projectB, displayId: 1)

        let input = """
        {"name":"Orphan Check","type":"bug","project":"\(projectA.name)","milestoneDisplayId":1}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "MILESTONE_PROJECT_MISMATCH")

        let descriptor = FetchDescriptor<TransitTask>()
        let tasks = try svc.context.fetch(descriptor)
        #expect(tasks.isEmpty, "Task should not be created when milestone belongs to a different project")
    }

    // Regression test for T-558: verify that task cleanup via context.delete + save
    // removes a persisted task. This validates the cleanup mechanism used in
    // CreateTaskIntent.execute when setMilestone fails after task creation.
    @Test func taskCleanupDeletesPersistedTask() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        // Create a task (simulating what execute does before setMilestone)
        let task = try await svc.task.createTask(
            name: "T-558 Orphan Test",
            description: nil,
            type: .bug,
            project: project
        )

        // Verify the task exists
        let beforeDescriptor = FetchDescriptor<TransitTask>()
        let beforeTasks = try svc.context.fetch(beforeDescriptor)
        #expect(beforeTasks.count == 1)

        // Simulate the cleanup path from the T-558 fix:
        // projectService.context.delete(task); try? projectService.context.save()
        svc.project.context.delete(task)
        try svc.project.context.save()

        // Verify the task was removed
        let afterDescriptor = FetchDescriptor<TransitTask>()
        let afterTasks = try svc.context.fetch(afterDescriptor)
        #expect(afterTasks.isEmpty, "Task should be deleted after cleanup [T-558]")
    }

    @Test func createTaskWithoutMilestoneServiceSkipsMilestone() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"Task","type":"feature","project":"\(project.name)","milestoneDisplayId":1}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        // Should succeed — milestone param is silently ignored without milestoneService
        #expect(parsed["taskId"] is String)
        #expect(parsed["milestone"] == nil)
    }
}
