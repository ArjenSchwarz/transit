#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-613: non-integer milestoneDisplayId inputs must return a validation error
/// instead of silently falling through to "not provided" behavior.
@MainActor @Suite(.serialized)
struct NonIntegerMilestoneDisplayIdTests {

    // MARK: - Intent Test Helpers

    private struct IntentServices {
        let task: TaskService
        let project: ProjectService
        let milestone: MilestoneService
        let context: ModelContext
    }

    private func makeIntentServices() throws -> IntentServices {
        let context = try TestModelContainer.newContext()
        let taskAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        return IntentServices(
            task: TaskService(modelContext: context, displayIDAllocator: taskAllocator),
            project: ProjectService(modelContext: context),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - MCP create_task

    @Test func mcpCreateTaskRejectsStringMilestoneDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task",
                "type": "bug",
                "projectId": project.id.uuidString,
                "milestoneDisplayId": "abc"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneDisplayId must be an integer"))
    }

    @Test func mcpCreateTaskRejectsFractionalMilestoneDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task",
                "type": "bug",
                "projectId": project.id.uuidString,
                "milestoneDisplayId": 1.5
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneDisplayId must be an integer"))
    }

    // MARK: - MCP update_task

    @Test func mcpUpdateTaskRejectsStringMilestoneDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: [
                "displayId": task.permanentDisplayId!,
                "milestoneDisplayId": "abc"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneDisplayId must be an integer"))
    }

    @Test func mcpUpdateTaskRejectsFractionalMilestoneDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: [
                "displayId": task.permanentDisplayId!,
                "milestoneDisplayId": 1.5
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneDisplayId must be an integer"))
    }

    // MARK: - MCP query_tasks

    @Test func mcpQueryTasksRejectsStringMilestoneDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["milestoneDisplayId": "abc"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneDisplayId must be an integer"))
    }

    @Test func mcpQueryTasksRejectsFractionalMilestoneDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["milestoneDisplayId": 1.5]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestoneDisplayId must be an integer"))
    }

    // MARK: - Intent: CreateTaskIntent

    @Test func intentCreateTaskRejectsStringMilestoneDisplayId() async throws {
        let svc = try makeIntentServices()
        makeProject(in: svc.context)

        let input = """
        {"name":"Task","type":"bug","project":"Test","milestoneDisplayId":"abc"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestoneDisplayId must be an integer") == true)
    }

    @Test func intentCreateTaskRejectsFractionalMilestoneDisplayId() async throws {
        let svc = try makeIntentServices()
        makeProject(in: svc.context)

        // JSON number 1.5 will be parsed as Double by JSONSerialization
        let input = """
        {"name":"Task","type":"bug","project":"Test","milestoneDisplayId":1.5}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task,
            projectService: svc.project, milestoneService: svc.milestone
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestoneDisplayId must be an integer") == true)
    }

    // MARK: - Intent: IntentHelpers.assignMilestone

    @Test func assignMilestoneRejectsStringMilestoneDisplayId() async throws {
        let svc = try makeIntentServices()
        let project = makeProject(in: svc.context)
        let task = try await svc.task.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let json: [String: Any] = ["milestoneDisplayId": "abc"]
        let error = IntentHelpers.assignMilestone(
            from: json, to: task, milestoneService: svc.milestone
        )

        let errorString = try #require(error)
        let parsed = try parseJSON(errorString)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestoneDisplayId must be an integer") == true)
    }

    @Test func assignMilestoneRejectsFractionalMilestoneDisplayId() async throws {
        let svc = try makeIntentServices()
        let project = makeProject(in: svc.context)
        let task = try await svc.task.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let json: [String: Any] = ["milestoneDisplayId": 1.5]
        let error = IntentHelpers.assignMilestone(
            from: json, to: task, milestoneService: svc.milestone
        )

        let errorString = try #require(error)
        let parsed = try parseJSON(errorString)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestoneDisplayId must be an integer") == true)
    }
}

#endif
