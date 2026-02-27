#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Tests for milestone-related functionality in existing MCP tools
/// (update_task, create_task, query_tasks, get_projects).
@MainActor @Suite(.serialized)
struct MCPMilestoneIntegrationTests {

    // MARK: - update_task (milestone assignment)

    @Test func updateTaskSetMilestoneByDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        _ = try await env.taskService.createTask(
            name: "Task A", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: [
                "displayId": 1,
                "milestoneDisplayId": milestone.permanentDisplayId!
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let milestoneInfo = try #require(result["milestone"] as? [String: Any])
        #expect(milestoneInfo["name"] as? String == "v1.0")
    }

    @Test func updateTaskSetMilestoneByName() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)
        _ = try await env.taskService.createTask(
            name: "Task A", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": 1, "milestone": "v1.0"]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let milestoneInfo = try #require(result["milestone"] as? [String: Any])
        #expect(milestoneInfo["name"] as? String == "v1.0")
    }

    @Test func updateTaskClearMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        let task = try await env.taskService.createTask(
            name: "Task A", description: nil, type: .feature, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": 1, "clearMilestone": true]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        #expect(result["milestone"] == nil)
    }

    @Test func updateTaskMilestoneProjectMismatchReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let projectA = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let projectB = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: projectB
        )
        _ = try await env.taskService.createTask(
            name: "Task A", description: nil, type: .feature, project: projectA
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: [
                "displayId": 1,
                "milestoneDisplayId": milestone.permanentDisplayId!
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func updateTaskMilestoneNotFoundReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "Task A", description: nil, type: .feature, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": 1, "milestoneDisplayId": 999]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    // MARK: - create_task with milestone

    @Test func createTaskWithMilestoneByName() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "New Task",
                "type": "feature",
                "projectId": project.id.uuidString,
                "milestone": "v1.0"
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let milestoneInfo = try #require(result["milestone"] as? [String: Any])
        #expect(milestoneInfo["name"] as? String == "v1.0")
    }

    @Test func createTaskWithMilestoneByDisplayId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "New Task",
                "type": "feature",
                "projectId": project.id.uuidString,
                "milestoneDisplayId": milestone.permanentDisplayId!
            ]
        ))

        let result = try MCPTestHelpers.decodeResult(response)
        let milestoneInfo = try #require(result["milestone"] as? [String: Any])
        #expect(milestoneInfo["name"] as? String == "v1.0")
    }

    @Test func createTaskWithNonexistentMilestoneReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "New Task",
                "type": "feature",
                "projectId": project.id.uuidString,
                "milestone": "nonexistent"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    // MARK: - T-240 regression: create_task must not create tasks when milestone validation fails

    @Test func createTaskWithNonexistentMilestoneByNameDoesNotCreateTask() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Orphan Candidate",
                "type": "bug",
                "projectId": project.id.uuidString,
                "milestone": "does-not-exist"
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorText = try MCPTestHelpers.errorText(response)
        #expect(errorText.contains("does-not-exist"), "Error should mention the milestone name")
        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when milestone validation fails")
    }

    @Test func createTaskWithNonexistentMilestoneByDisplayIdDoesNotCreateTask() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Orphan Candidate",
                "type": "bug",
                "projectId": project.id.uuidString,
                "milestoneDisplayId": 999
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorText = try MCPTestHelpers.errorText(response)
        #expect(errorText.contains("999"), "Error should mention the milestone displayId")
        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when milestone validation fails")
    }

    @Test func createTaskWithMilestoneProjectMismatchDoesNotCreateTask() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let projectA = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let projectB = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: projectB
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Orphan Candidate",
                "type": "feature",
                "projectId": projectA.id.uuidString,
                "milestoneDisplayId": milestone.permanentDisplayId!
            ]
        ))

        #expect(try MCPTestHelpers.isError(response))
        let errorText = try MCPTestHelpers.errorText(response)
        #expect(errorText.contains("same project"), "Error should mention project mismatch")
        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty, "Task must not be created when milestone belongs to a different project")
    }

    // MARK: - query_tasks with milestone filter

    @Test func queryTasksFilterByMilestone() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        let task1 = try await env.taskService.createTask(
            name: "In Milestone", description: nil, type: .feature, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task1)
        _ = try await env.taskService.createTask(
            name: "No Milestone", description: nil, type: .bug, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["milestoneDisplayId": 1]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "In Milestone")
    }

    @Test func queryTasksIncludesMilestoneInfo() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "v1.0", description: nil, project: project
        )
        let task = try await env.taskService.createTask(
            name: "Task", description: nil, type: .feature, project: project
        )
        try env.milestoneService.setMilestone(milestone, on: task)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let first = try #require(results.first)
        let milestoneInfo = try #require(first["milestone"] as? [String: Any])
        #expect(milestoneInfo["name"] as? String == "v1.0")
    }

    // MARK: - get_projects includes milestones

    @Test func getProjectsIncludesMilestones() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.milestoneService.createMilestone(name: "v1.0", description: nil, project: project)
        _ = try await env.milestoneService.createMilestone(name: "v2.0", description: nil, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "get_projects",
            arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let first = try #require(results.first)
        let milestones = try #require(first["milestones"] as? [[String: Any]])
        #expect(milestones.count == 2)
        let names = milestones.compactMap { $0["name"] as? String }
        #expect(names.contains("v1.0"))
        #expect(names.contains("v2.0"))
    }
}

#endif
