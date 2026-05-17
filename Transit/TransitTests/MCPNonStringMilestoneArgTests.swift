#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1114: a present-but-non-string `milestone` argument on
/// MCP `create_task` and `update_task` must be rejected with an INVALID_INPUT
/// error rather than silently dropped. Previously `args["milestone"] as? String`
/// returned nil for numbers, booleans, arrays, etc., and the operation completed
/// without assigning the requested milestone.
@MainActor @Suite(.serialized)
struct MCPNonStringMilestoneArgTests {

    // MARK: - create_task

    @Test func mcpCreateTaskRejectsNumericMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task",
                "type": "bug",
                "projectId": project.id.uuidString,
                "milestone": 42
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestone must be a string"))

        // Task must not have been created.
        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when milestone validation fails")
    }

    @Test func mcpCreateTaskRejectsBooleanMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task",
                "type": "bug",
                "projectId": project.id.uuidString,
                "milestone": true
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestone must be a string"))

        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when milestone validation fails")
    }

    @Test func mcpCreateTaskRejectsArrayMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task",
                "type": "bug",
                "projectId": project.id.uuidString,
                "milestone": ["v1.0"]
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestone must be a string"))

        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when milestone validation fails")
    }

    @Test func mcpCreateTaskRejectsNullMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task",
                "type": "bug",
                "projectId": project.id.uuidString,
                "milestone": NSNull()
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestone must be a string"))

        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when milestone validation fails")
    }

    // MARK: - update_task

    @Test func mcpUpdateTaskRejectsNumericMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestone": 42]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestone must be a string"))
        #expect(task.milestone?.id == milestone.id, "Existing milestone must remain assigned")
    }

    @Test func mcpUpdateTaskRejectsBooleanMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestone": true]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestone must be a string"))
        #expect(task.milestone?.id == milestone.id, "Existing milestone must remain assigned")
    }

    @Test func mcpUpdateTaskRejectsArrayMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestone": ["v1.0"]]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestone must be a string"))
        #expect(task.milestone?.id == milestone.id, "Existing milestone must remain assigned")
    }

    @Test func mcpUpdateTaskRejectsNullMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestone": NSNull()]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let text = try MCPTestHelpers.errorText(response)
        #expect(text.contains("milestone must be a string"))
        #expect(task.milestone?.id == milestone.id, "Existing milestone must remain assigned")
    }
}

#endif
