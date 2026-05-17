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

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let result = QueryTasksIntent.execute(
            input: "{\"milestoneDisplayId\":1}",
            projectService: projectService,
            taskService: taskService,
            milestoneService: milestoneService
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

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let result = QueryTasksIntent.execute(
            input: "{\"milestone\":\"v1.0\"}",
            projectService: projectService,
            taskService: taskService,
            milestoneService: milestoneService
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

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let result = QueryTasksIntent.execute(
            input: "",
            projectService: projectService,
            taskService: taskService,
            milestoneService: milestoneService
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

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let result = QueryTasksIntent.execute(
            input: "",
            projectService: projectService,
            taskService: taskService,
            milestoneService: milestoneService
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        #expect(parsed.first?["milestone"] == nil)
    }

    // MARK: - Duplicate milestoneDisplayId regression (T-1146)

    /// When two milestones share the same `permanentDisplayId` (possible via CloudKit sync
    /// conflicts), `QueryTasksIntent` must reject the filter as ambiguous rather than
    /// silently returning tasks from every matching milestone. Mirrors the
    /// `MCPToolHandler.handleQueryTasks` behavior, which already routes through
    /// `MilestoneService.findByDisplayID` and surfaces `INTERNAL_ERROR` on duplicates.
    @Test func filterByMilestoneDisplayIdRejectsDuplicates() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let milestoneA = makeMilestone(in: context, name: "v1.0", project: project, displayId: 7)
        let milestoneB = makeMilestone(in: context, name: "v1.0-alt", project: project, displayId: 7)
        makeTask(in: context, name: "In milestone A", project: project, milestone: milestoneA, displayId: 20)
        makeTask(in: context, name: "In milestone B", project: project, milestone: milestoneB, displayId: 21)

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let result = QueryTasksIntent.execute(
            input: "{\"milestoneDisplayId\":7}",
            projectService: projectService,
            taskService: taskService,
            milestoneService: milestoneService
        )

        let data = try #require(result.data(using: .utf8))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["error"] as? String == "INTERNAL_ERROR")
        let hint = json["hint"] as? String ?? ""
        #expect(hint.contains("7"))
    }

    /// When the requested `milestoneDisplayId` does not match any milestone, the intent
    /// must return an empty array (consistent with other lookup paths that treat unknown
    /// display IDs as "no results").
    @Test func filterByMilestoneDisplayIdReturnsEmptyWhenUnknown() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let milestone = makeMilestone(in: context, name: "v1.0", project: project, displayId: 1)
        makeTask(in: context, name: "In milestone", project: project, milestone: milestone, displayId: 10)

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let result = QueryTasksIntent.execute(
            input: "{\"milestoneDisplayId\":999}",
            projectService: projectService,
            taskService: taskService,
            milestoneService: milestoneService
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.isEmpty)
    }
}
