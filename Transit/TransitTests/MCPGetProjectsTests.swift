#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPGetProjectsTests {

    @Test func getProjectsReturnsCorrectFieldsAndSortOrder() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let bravo = MCPTestHelpers.makeProject(in: env.context, name: "Bravo")
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.taskService.createTask(name: "T1", description: nil, type: .feature, project: alpha)
        _ = try await env.taskService.createTask(name: "T2", description: nil, type: .bug, project: bravo)
        _ = try await env.taskService.createTask(name: "T3", description: nil, type: .chore, project: bravo)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "get_projects", arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)

        let first = try #require(results.first)
        #expect(first["name"] as? String == "Alpha")
        #expect(first["projectId"] is String)
        #expect(first["description"] is String)
        #expect(first["colorHex"] is String)
        #expect(first["activeTaskCount"] as? Int == 1)

        let second = try #require(results.last)
        #expect(second["name"] as? String == "Bravo")
        #expect(second["activeTaskCount"] as? Int == 2)
    }

    @Test func getProjectsReturnsEmptyArrayWhenNoProjects() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "get_projects", arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.isEmpty)
    }

    @Test func getProjectsIncludesGitRepoWhenSetAndOmitsWhenNil() async throws {
        let env = try MCPTestHelpers.makeEnv()
        MCPTestHelpers.makeProject(in: env.context, name: "WithRepo", gitRepo: "https://github.com/org/repo")
        MCPTestHelpers.makeProject(in: env.context, name: "WithoutRepo")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "get_projects", arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)

        let withRepo = try #require(results.first { $0["name"] as? String == "WithRepo" })
        #expect(withRepo["gitRepo"] as? String == "https://github.com/org/repo")

        let withoutRepo = try #require(results.first { $0["name"] as? String == "WithoutRepo" })
        #expect(withoutRepo["gitRepo"] == nil)
    }

    @Test func getProjectsActiveTaskCountExcludesTerminalTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let doneTask = try await env.taskService.createTask(
            name: "Done", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: doneTask, to: .done)
        let abandonedTask = try await env.taskService.createTask(
            name: "Abandoned", description: nil, type: .bug, project: project
        )
        try env.taskService.updateStatus(task: abandonedTask, to: .abandoned)
        _ = try await env.taskService.createTask(
            name: "Active", description: nil, type: .chore, project: project
        )

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "get_projects", arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        let first = try #require(results.first)
        #expect(first["activeTaskCount"] as? Int == 1)
    }
}

#endif
