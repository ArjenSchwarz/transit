import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-370: Intent JSON displayId parsing rejects numeric values.
///
/// JSONSerialization deserializes JSON integers as NSNumber, which bridges to Double in Swift.
/// Code using `as? Int` silently fails for these values. These tests verify that numeric
/// displayId and milestoneDisplayId values are accepted in all intent and MCP code paths.
@MainActor @Suite(.serialized)
struct NumericDisplayIdParsingTests {

    // MARK: - Helpers

    private func makeService() throws -> (TaskService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        return (service, context)
    }

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test", description: "Test", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        return project
    }

    private func makeTask(
        in context: ModelContext,
        project: Project,
        displayId: Int,
        status: TaskStatus = .idea
    ) -> TransitTask {
        let task = TransitTask(
            name: "Task \(displayId)", type: .feature, project: project,
            displayID: .permanent(displayId)
        )
        StatusEngine.initializeNewTask(task)
        if status != .idea {
            StatusEngine.applyTransition(task: task, to: status)
        }
        context.insert(task)
        return task
    }

    private func makeMilestoneService(context: ModelContext) -> MilestoneService {
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return MilestoneService(modelContext: context, displayIDAllocator: allocator)
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - IntentHelpers.resolveTask

    @Test func resolveTaskAcceptsNumericDisplayId() throws {
        let (taskService, context) = try makeService()
        let project = makeProject(in: context)
        makeTask(in: context, project: project, displayId: 42)

        // JSONSerialization parses 42 as NSNumber/Double, not Int
        let json = try parseJSON("""
        {"displayId": 42}
        """)

        let result = IntentHelpers.resolveTask(from: json, taskService: taskService)
        switch result {
        case .success(let task):
            #expect(task.permanentDisplayId == 42)
        case .failure(let error):
            Issue.record("Expected success but got: \(error)")
        }
    }

    // MARK: - IntentHelpers.assignMilestone

    @Test func assignMilestoneAcceptsNumericMilestoneDisplayId() throws {
        let (taskService, context) = try makeService()
        let project = makeProject(in: context)
        let task = makeTask(in: context, project: project, displayId: 1)
        let milestoneService = makeMilestoneService(context: context)
        let milestone = Milestone(name: "Sprint 1", project: project, displayID: .permanent(5))
        context.insert(milestone)

        // JSONSerialization parses 5 as NSNumber/Double
        let json = try parseJSON("""
        {"milestoneDisplayId": 5}
        """)

        let error = IntentHelpers.assignMilestone(
            from: json, to: task, milestoneService: milestoneService
        )
        #expect(error == nil, "Expected no error but got: \(error ?? "")")
        #expect(task.milestone?.name == "Sprint 1")
    }

    // MARK: - UpdateStatusIntent

    @Test func updateStatusAcceptsNumericDisplayId() throws {
        let (taskService, context) = try makeService()
        let project = makeProject(in: context)
        makeTask(in: context, project: project, displayId: 42)

        // This JSON will have displayId deserialized as Double by JSONSerialization
        let input = """
        {"displayId": 42, "status": "planning"}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: taskService)
        let parsed = try parseJSON(result)

        // Before the fix, this would return INVALID_INPUT because `as? Int` fails for Double
        #expect(parsed["error"] as? String == nil, "Expected no error but got: \(parsed["error"] ?? "nil")")
        #expect(parsed["status"] as? String == "planning")
    }
}

// MARK: - MCP Tool Handler Tests

#if os(macOS)
@MainActor @Suite(.serialized)
struct NumericDisplayIdMCPTests {

    // MARK: - MCP resolveTask (update_task_status)

    @Test func mcpUpdateStatusAcceptsNumericDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = TransitTask(
            name: "Test", type: .feature, project: project,
            displayID: .permanent(42)
        )
        StatusEngine.initializeNewTask(task)
        env.context.insert(task)

        // Double value simulates what JSONSerialization produces from {"displayId": 42}
        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(
                tool: "update_task_status",
                arguments: ["displayId": 42 as Double, "status": "planning"]
            )
        )

        let isErr = try MCPTestHelpers.isError(response)
        #expect(!isErr, "Expected success but got error")
        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["status"] as? String == "planning")
    }

    // MARK: - MCP resolveTask (query_tasks)

    @Test func mcpQueryTasksAcceptsNumericDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = TransitTask(
            name: "Test", type: .feature, project: project,
            displayID: .permanent(10)
        )
        StatusEngine.initializeNewTask(task)
        env.context.insert(task)

        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(
                tool: "query_tasks",
                arguments: ["displayId": 10 as Double]
            )
        )

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
    }

    // MARK: - MCP resolveMilestone (query_milestones)

    @Test func mcpQueryMilestonesAcceptsNumericDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = Milestone(name: "Sprint 1", project: project, displayID: .permanent(3))
        env.context.insert(milestone)

        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(
                tool: "query_milestones",
                arguments: ["displayId": 3 as Double]
            )
        )

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
    }

    // MARK: - MCP create_task with milestoneDisplayId

    @Test func mcpCreateTaskAcceptsNumericMilestoneDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = Milestone(name: "Sprint 1", project: project, displayID: .permanent(1))
        env.context.insert(milestone)

        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(
                tool: "create_task",
                arguments: [
                    "name": "New task",
                    "type": "feature",
                    "project": "Test Project",
                    "milestoneDisplayId": 1 as Double
                ]
            )
        )

        let isErr = try MCPTestHelpers.isError(response)
        #expect(!isErr, "Expected success but got error")
    }

    // MARK: - MCP update_task with milestoneDisplayId

    @Test func mcpUpdateTaskAcceptsNumericMilestoneDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = TransitTask(
            name: "Test", type: .feature, project: project,
            displayID: .permanent(42)
        )
        StatusEngine.initializeNewTask(task)
        env.context.insert(task)

        let milestone = Milestone(name: "Sprint 1", project: project, displayID: .permanent(1))
        env.context.insert(milestone)

        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(
                tool: "update_task",
                arguments: ["displayId": 42 as Double, "milestoneDisplayId": 1 as Double]
            )
        )

        let isErr = try MCPTestHelpers.isError(response)
        #expect(!isErr, "Expected success but got error")
    }

    // MARK: - MCP query_tasks with milestoneDisplayId filter

    @Test func mcpQueryTasksMilestoneFilterAcceptsNumericDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = Milestone(name: "Sprint 1", project: project, displayID: .permanent(2))
        env.context.insert(milestone)

        let task = TransitTask(
            name: "Test", type: .feature, project: project,
            displayID: .permanent(10)
        )
        StatusEngine.initializeNewTask(task)
        task.milestone = milestone
        env.context.insert(task)

        let response = await env.handler.handle(
            MCPTestHelpers.toolCallRequest(
                tool: "query_tasks",
                arguments: ["milestoneDisplayId": 2 as Double]
            )
        )

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
    }
}
#endif
