#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-613: non-integer milestoneDisplayId inputs must return a validation error
/// instead of silently falling through to "not provided" behavior.
@MainActor @Suite(.serialized)
struct NonIntegerMilestoneDisplayIdTests {

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
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator)

        let project = Project(name: "Test", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let input = """
        {"name":"Task","type":"bug","project":"Test","milestoneDisplayId":"abc"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: taskService,
            projectService: projectService, milestoneService: milestoneService
        )

        let data = try #require(result.data(using: .utf8))
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestoneDisplayId must be an integer") == true)
    }

    @Test func intentCreateTaskRejectsFractionalMilestoneDisplayId() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator)

        let project = Project(name: "Test", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        // JSON number 1.5 will be parsed as Double by JSONSerialization
        let input = """
        {"name":"Task","type":"bug","project":"Test","milestoneDisplayId":1.5}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: taskService,
            projectService: projectService, milestoneService: milestoneService
        )

        let data = try #require(result.data(using: .utf8))
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestoneDisplayId must be an integer") == true)
    }

    // MARK: - Intent: IntentHelpers.assignMilestone

    @Test func assignMilestoneRejectsStringMilestoneDisplayId() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator)

        let project = Project(name: "Test", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        let task = try await taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let json: [String: Any] = ["milestoneDisplayId": "abc"]
        let error = IntentHelpers.assignMilestone(
            from: json, to: task, milestoneService: milestoneService
        )

        let errorString = try #require(error)
        let data = try #require(errorString.data(using: .utf8))
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestoneDisplayId must be an integer") == true)
    }

    @Test func assignMilestoneRejectsFractionalMilestoneDisplayId() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator)

        let project = Project(name: "Test", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        let task = try await taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )

        let json: [String: Any] = ["milestoneDisplayId": 1.5]
        let error = IntentHelpers.assignMilestone(
            from: json, to: task, milestoneService: milestoneService
        )

        let errorString = try #require(error)
        let data = try #require(errorString.data(using: .utf8))
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestoneDisplayId must be an integer") == true)
    }
}

#endif
