#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPStatusFilterIntegrationTests {

    @Test func multiStatusWithProjectFilterReturnsCorrectSubset() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let beta = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        _ = try await env.taskService.createTask(
            name: "AlphaIdea", description: nil, type: .feature, project: alpha
        )
        let alphaPlanning = try await env.taskService.createTask(
            name: "AlphaPlanning", description: nil, type: .feature, project: alpha
        )
        try env.taskService.updateStatus(task: alphaPlanning, to: .planning)
        _ = try await env.taskService.createTask(
            name: "BetaIdea", description: nil, type: .bug, project: beta
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": ["idea", "planning"], "project": "Alpha"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let names = Set(results.compactMap { $0["name"] as? String })
        #expect(names == ["AlphaIdea", "AlphaPlanning"])
    }

    @Test func exclusionFilterWithTypeFilterComposesCorrectly() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(
            name: "ActiveBug", description: nil, type: .bug, project: project
        )
        _ = try await env.taskService.createTask(
            name: "ActiveFeature", description: nil, type: .feature, project: project
        )
        let doneBug = try await env.taskService.createTask(
            name: "DoneBug", description: nil, type: .bug, project: project
        )
        try env.taskService.updateStatus(task: doneBug, to: .planning)
        try env.taskService.updateStatus(task: doneBug, to: .spec)
        try env.taskService.updateStatus(task: doneBug, to: .inProgress)
        try env.taskService.updateStatus(task: doneBug, to: .done)

        // Exclude done, filter to bugs only
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["not_status": ["done"], "type": "bug"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "ActiveBug")
    }

    @Test func unfinishedFlagWithDisplayIdLookupStillWorks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Active", description: nil, type: .feature, project: project
        )
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": displayId, "unfinished": true]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Active")
    }

    @Test func unfinishedFlagWithDisplayIdLookupExcludesDoneTask() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = try await env.taskService.createTask(
            name: "Done", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: task, to: .planning)
        try env.taskService.updateStatus(task: task, to: .spec)
        try env.taskService.updateStatus(task: task, to: .inProgress)
        try env.taskService.updateStatus(task: task, to: .done)
        let displayId = try #require(task.permanentDisplayId)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["displayId": displayId, "unfinished": true]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    @Test func singleStringStatusWithProjectFilterWorks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context, name: "MyProject")
        _ = try await env.taskService.createTask(
            name: "Idea", description: nil, type: .feature, project: project
        )
        let planningTask = try await env.taskService.createTask(
            name: "Planning", description: nil, type: .bug, project: project
        )
        try env.taskService.updateStatus(task: planningTask, to: .planning)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["status": "planning", "project": "MyProject"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Planning")
    }
}

#endif
