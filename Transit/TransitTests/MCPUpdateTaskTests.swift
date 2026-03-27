#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Tests for the MCP `update_task` tool handler, including milestone assignment
/// and the T-531 fix for save-failure rollback.
@MainActor @Suite(.serialized)
struct MCPUpdateTaskTests {

    @Test func setMilestoneByDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let milestoneDisplayId = try #require(milestone.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestoneDisplayId": milestoneDisplayId]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "Task")
        #expect(task.milestone?.id == milestone.id)
    }

    @Test func clearMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)
        #expect(task.milestone != nil)

        let taskDisplayId = try #require(task.permanentDisplayId)
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "clearMilestone": true]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["name"] as? String == "Task")
        #expect(task.milestone == nil)
    }

    @Test func milestoneProjectMismatchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let projectA = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let projectB = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: projectA
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: projectB
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let milestoneDisplayId = try #require(milestone.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestoneDisplayId": milestoneDisplayId]
        ))

        #expect(try MCPTestHelpers.isError(response))
        // T-531: After error, task must not have a dirty milestone reference
        #expect(task.milestone == nil, "Task milestone should remain nil after failed update")
    }

    @Test func milestoneNotFoundReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestoneDisplayId": 999]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    /// T-531 regression: handleUpdateTask must not leave unsaved in-memory changes
    /// when the milestone assignment path errors out. Before the fix, setMilestone
    /// saved independently of the final save(), so a mid-handler error could leave
    /// dirty state on the shared context.
    @Test func doesNotLeakDirtyStateOnMilestoneError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let projectA = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let projectB = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: projectA
        )
        let milestone = try await env.milestoneService.createMilestone(
            name: "Sprint 1", description: nil, project: projectB
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let milestoneDisplayId = try #require(milestone.permanentDisplayId)

        // Attempt assignment with project mismatch — should fail
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestoneDisplayId": milestoneDisplayId]
        ))

        #expect(try MCPTestHelpers.isError(response))

        // The context should have no pending changes after the error
        #expect(!env.context.hasChanges, "Context should not have dirty state after failed update_task")
        #expect(task.milestone == nil, "Task milestone should be nil after failed cross-project assignment")
    }
}

#endif
