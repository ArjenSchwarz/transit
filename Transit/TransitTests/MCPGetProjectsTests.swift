#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPGetProjectsTests {

    private struct ScopedMilestoneFetchFailure: Swift.Error, CustomStringConvertible {
        var description: String { "simulated scoped milestone fetch failure" }
    }

    private struct FailingScopedMilestoneFetcher: ModelFetching {
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            throw ScopedMilestoneFetchFailure()
        }
    }

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

    @Test
    func getProjectsMilestoneFetchFailureReturnsExactToolErrorWithoutPartialProjects() async throws {
        let env = try MCPTestHelpers.makeEnv(milestoneServiceFetcher: FailingScopedMilestoneFetcher())
        MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        MCPTestHelpers.makeProject(in: env.context, name: "Beta")

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "get_projects", arguments: [:]
        ))

        #expect(
            try MCPTestHelpers.isError(response),
            "A milestone fetch failure must not return a partial project list"
        )
        #expect(
            try MCPTestHelpers.errorText(response)
                == "Failed to fetch milestones: simulated scoped milestone fetch failure"
        )
    }

    @Test func getProjectsPreservesEmptyMilestonesAndScopesOtherProjects() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let beta = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        _ = try await env.milestoneService.createMilestone(name: "Beta 1", description: nil, project: beta)
        _ = try await env.milestoneService.createMilestone(name: "Beta 2", description: nil, project: beta)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "get_projects", arguments: [:]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)

        let alphaResult = try #require(results.first { $0["projectId"] as? String == alpha.id.uuidString })
        #expect(alphaResult["milestones"] == nil)

        let betaResult = try #require(results.first { $0["projectId"] as? String == beta.id.uuidString })
        let milestones = try #require(betaResult["milestones"] as? [[String: Any]])
        #expect(milestones.count == 2)
        #expect(Set(milestones.compactMap { $0["name"] as? String }) == ["Beta 1", "Beta 2"])
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
