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
