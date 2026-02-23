import Foundation
import SwiftData
import Testing
@testable import Transit

/// Milestone-related tests for QueryTasksIntent [req 13.7]
@MainActor @Suite(.serialized)
struct QueryTasksIntentMilestoneTests {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        try TestModelContainer.newContext()
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

    @discardableResult
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

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    // MARK: - Milestone Filter

    @Test func filterByMilestoneDisplayId() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let milestone = makeMilestone(in: context, name: "v1.0", project: project, displayId: 1)
        makeTask(in: context, name: "In milestone", project: project, milestone: milestone, displayId: 10)
        makeTask(in: context, name: "No milestone", project: project, displayId: 11)

        let projectService = ProjectService(modelContext: context)
        let result = QueryTasksIntent.execute(
            input: "{\"milestoneDisplayId\":1}",
            projectService: projectService,
            modelContext: context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "In milestone")
    }

    @Test func filterByMilestoneName() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let milestone = makeMilestone(in: context, name: "v1.0", project: project, displayId: 1)
        makeTask(in: context, name: "In milestone", project: project, milestone: milestone, displayId: 10)
        makeTask(in: context, name: "No milestone", project: project, displayId: 11)

        let projectService = ProjectService(modelContext: context)
        let result = QueryTasksIntent.execute(
            input: "{\"milestone\":\"v1.0\"}",
            projectService: projectService,
            modelContext: context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["name"] as? String == "In milestone")
    }

    @Test func taskResponseIncludesMilestoneInfo() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let milestone = makeMilestone(in: context, name: "v1.0", project: project, displayId: 1)
        makeTask(in: context, name: "Task", project: project, milestone: milestone, displayId: 10)

        let projectService = ProjectService(modelContext: context)
        let result = QueryTasksIntent.execute(
            input: "", projectService: projectService, modelContext: context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        let milestoneInfo = parsed.first?["milestone"] as? [String: Any]
        #expect(milestoneInfo?["name"] as? String == "v1.0")
        #expect(milestoneInfo?["displayId"] as? Int == 1)
    }

    @Test func taskWithoutMilestoneOmitsMilestoneField() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        makeTask(in: context, name: "Task", project: project, displayId: 10)

        let projectService = ProjectService(modelContext: context)
        let result = QueryTasksIntent.execute(
            input: "", projectService: projectService, modelContext: context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["milestone"] == nil)
    }
}
