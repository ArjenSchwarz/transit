#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1192: a present-but-non-string `description` argument
/// on MCP `create_task` and `create_milestone` must be rejected with a
/// validation error rather than silently dropped. Previously
/// `args["description"] as? String` returned nil for numbers, booleans, arrays,
/// etc., and the object was created without the description, making a malformed
/// request look successful.
@MainActor @Suite(.serialized)
struct MCPNonStringDescriptionTests {

    // MARK: - create_task

    @Test func mcpCreateTaskRejectsNumericDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task", "type": "bug",
                "projectId": project.id.uuidString, "description": 123
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("description must be a string"))

        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when description validation fails")
    }

    @Test func mcpCreateTaskRejectsBooleanDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task", "type": "bug",
                "projectId": project.id.uuidString, "description": false
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("description must be a string"))

        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when description validation fails")
    }

    @Test func mcpCreateTaskRejectsArrayDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task", "type": "bug",
                "projectId": project.id.uuidString, "description": ["x"]
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("description must be a string"))

        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when description validation fails")
    }

    @Test func mcpCreateTaskRejectsNullDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task", "type": "bug",
                "projectId": project.id.uuidString, "description": NSNull()
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("description must be a string"))

        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when description validation fails")
    }

    @Test func mcpCreateTaskAcceptsStringDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Task", "type": "bug",
                "projectId": project.id.uuidString, "description": "A description"
            ]
        ))

        #expect(try !MCPTestHelpers.isError(response))
        let task = try #require(try env.context.fetch(FetchDescriptor<TransitTask>()).first)
        #expect(task.taskDescription == "A description")
    }

    // MARK: - create_milestone

    @Test func mcpCreateMilestoneRejectsNumericDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: [
                "name": "v1.0", "projectId": project.id.uuidString, "description": 123
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("description must be a string"))

        let milestones = try env.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.isEmpty, "Milestone must not be created when description validation fails")
    }

    @Test func mcpCreateMilestoneRejectsBooleanDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: [
                "name": "v1.0", "projectId": project.id.uuidString, "description": true
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("description must be a string"))

        let milestones = try env.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.isEmpty, "Milestone must not be created when description validation fails")
    }

    @Test func mcpCreateMilestoneRejectsArrayDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: [
                "name": "v1.0", "projectId": project.id.uuidString, "description": ["x"]
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("description must be a string"))

        let milestones = try env.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.isEmpty, "Milestone must not be created when description validation fails")
    }

    @Test func mcpCreateMilestoneRejectsNullDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: [
                "name": "v1.0", "projectId": project.id.uuidString, "description": NSNull()
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("description must be a string"))

        let milestones = try env.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.isEmpty, "Milestone must not be created when description validation fails")
    }

    @Test func mcpCreateMilestoneAcceptsStringDescription() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: [
                "name": "v1.0", "projectId": project.id.uuidString, "description": "Beta release"
            ]
        ))

        #expect(try !MCPTestHelpers.isError(response))
        let milestone = try #require(try env.context.fetch(FetchDescriptor<Milestone>()).first)
        #expect(milestone.milestoneDescription == "Beta release")
    }
}

#endif
