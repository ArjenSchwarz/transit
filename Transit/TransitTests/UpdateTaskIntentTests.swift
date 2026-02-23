import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct UpdateTaskIntentTests {

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

    // MARK: - Milestone Assignment

    @Test func assignMilestoneByDisplayId() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, displayId: 10)

        let input = """
        {"displayId":10,"milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] as? String == task.id.uuidString)
        let milestoneInfo = parsed["milestone"] as? [String: Any]
        #expect(milestoneInfo?["name"] as? String == "v1.0")
        #expect(milestoneInfo?["displayId"] as? Int == 1)
        #expect(task.milestone?.id == milestone.id)
    }

    @Test func assignMilestoneByName() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, displayId: 10)

        let input = """
        {"displayId":10,"milestone":"v1.0"}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        let milestoneInfo = parsed["milestone"] as? [String: Any]
        #expect(milestoneInfo?["name"] as? String == "v1.0")
        #expect(task.milestone != nil)
    }

    @Test func clearMilestone() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, milestone: milestone, displayId: 10)

        let input = """
        {"displayId":10,"clearMilestone":true}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] as? String == task.id.uuidString)
        #expect(task.milestone == nil)
    }

    @Test func assignByTaskId() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)
        let task = makeTask(in: svc.context, name: "Task 1", project: project, displayId: 10)

        let input = """
        {"taskId":"\(task.id.uuidString)","milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] as? String == task.id.uuidString)
        #expect(task.milestone != nil)
    }

    // MARK: - Error Cases

    @Test func unknownTaskReturnsTaskNotFound() throws {
        let svc = try makeServices()

        let input = """
        {"displayId":999,"milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "TASK_NOT_FOUND")
    }

    @Test func unknownMilestoneReturnsMilestoneNotFound() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeTask(in: svc.context, name: "Task 1", project: project, displayId: 10)

        let input = """
        {"displayId":10,"milestoneDisplayId":999}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "MILESTONE_NOT_FOUND")
    }

    @Test func milestoneProjectMismatchReturnsError() throws {
        let svc = try makeServices()
        let alpha = makeProject(in: svc.context, name: "Alpha")
        let beta = makeProject(in: svc.context, name: "Beta")
        makeMilestone(in: svc.context, name: "v1.0", project: beta, displayId: 1)
        makeTask(in: svc.context, name: "Task 1", project: alpha, displayId: 10)

        let input = """
        {"displayId":10,"milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "MILESTONE_PROJECT_MISMATCH")
    }

    @Test func noTaskIdentifierReturnsInvalidInput() throws {
        let svc = try makeServices()

        let input = """
        {"milestoneDisplayId":1}
        """

        let result = UpdateTaskIntent.execute(
            input: input, taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func malformedJSONReturnsInvalidInput() throws {
        let svc = try makeServices()

        let result = UpdateTaskIntent.execute(
            input: "not json", taskService: svc.task,
            milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }
}
