#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPQueryProjectNameTests {

    private struct FetchFailure: Swift.Error {}

    private struct MilestoneFetchFailure: Swift.Error, CustomStringConvertible {
        var description: String { "simulated milestone fetch failure" }
    }

    private struct FailingProjectFetcher: ModelFetching {
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            throw FetchFailure()
        }
    }

    private struct FailingTaskFetcher: TaskFetching {
        func fetchAllTasks() throws -> [TransitTask] { throw FetchFailure() }
    }

    private struct FailingMilestoneFetcher: MilestoneFetching {
        func fetchAllMilestones() throws -> [Milestone] { throw MilestoneFetchFailure() }
    }

    @Test func queryByProjectNameReturnsMatchingTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let beta = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        _ = try await env.taskService.createTask(name: "A1", description: nil, type: .feature, project: alpha)
        _ = try await env.taskService.createTask(name: "B1", description: nil, type: .bug, project: beta)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "Alpha"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "A1")
    }

    @Test func queryByProjectNameIsCaseInsensitive() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context, name: "MyProject")
        _ = try await env.taskService.createTask(name: "Task", description: nil, type: .chore, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "myproject"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
    }

    @Test func queryByUnknownProjectNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "Nonexistent"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response) == "No project named \"Nonexistent\"")
    }

    @Test func queryByProjectIdReturnsMatchingTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let beta = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        _ = try await env.taskService.createTask(name: "A1", description: nil, type: .feature, project: alpha)
        _ = try await env.taskService.createTask(name: "B1", description: nil, type: .bug, project: beta)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["projectId": alpha.id.uuidString]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "A1")
    }

    @Test func queryWithMalformedProjectIdReturnsValidationError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["projectId": "not-a-uuid"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response) == "Invalid projectId: expected a UUID string")
    }

    @Test func queryWithNullProjectIdReturnsValidationError() async throws {
        let env = try MCPTestHelpers.makeEnv()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["projectId": NSNull()]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response) == "Invalid projectId: expected a UUID string")
    }

    @Test func queryProjectLookupFetchFailureReturnsInternalErrorEnvelope() async throws {
        let env = try MCPTestHelpers.makeEnv(projectFetcher: FailingProjectFetcher())
        let projectID = UUID()

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["projectId": projectID.uuidString]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).hasPrefix("Failed to fetch project:"))
    }

    @Test func queryTaskFetchFailureReturnsErrorEnvelope() async throws {
        let env = try MCPTestHelpers.makeEnv(taskFetcher: FailingTaskFetcher())

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: [:]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).hasPrefix("Failed to fetch tasks:"))
    }

    @Test func queryMilestoneNameFetchFailureReturnsExactErrorInsteadOfEmptyArray() async throws {
        let env = try MCPTestHelpers.makeEnv(milestoneFetcher: FailingMilestoneFetcher())

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["milestone": "v1.0"]
        ))

        #expect(try MCPTestHelpers.isError(response), "A failed filter fetch must not look like no matches")
        #expect(
            try MCPTestHelpers.errorText(response)
                == "Failed to fetch milestones: simulated milestone fetch failure"
        )
    }

    @Test func queryMilestoneFetchFailureDoesNotMaskMalformedStatus() async throws {
        let env = try MCPTestHelpers.makeEnv(milestoneFetcher: FailingMilestoneFetcher())

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["milestone": "v1.0", "status": "not-a-status"]
        ))

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("Invalid status: not-a-status"))
    }

    @Test func queryByNonexistentProjectIdMatchesIntentProjectNotFound() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let projectID = UUID()
        let projectIDString = projectID.uuidString.lowercased()

        let mcpResponse = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["projectId": projectIDString]
        ))

        #expect(try MCPTestHelpers.isError(mcpResponse))
        let mcpHint = try MCPTestHelpers.errorText(mcpResponse)

        let intentResponse = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(projectIDString)\"}",
            projectService: env.projectService,
            taskService: env.taskService,
            milestoneService: env.milestoneService
        )
        let intentData = try #require(intentResponse.data(using: .utf8))
        let intentJSON = try #require(
            try JSONSerialization.jsonObject(with: intentData) as? [String: Any]
        )
        #expect(intentJSON.count == 2)
        #expect(intentJSON["error"] as? String == "PROJECT_NOT_FOUND")
        #expect(intentJSON["hint"] as? String == mcpHint)
    }

    @Test func queryWithProjectIdAndProjectNameUsesProjectId() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let alpha = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let beta = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
        _ = try await env.taskService.createTask(name: "A1", description: nil, type: .feature, project: alpha)
        _ = try await env.taskService.createTask(name: "B1", description: nil, type: .bug, project: beta)

        // projectId points to Beta, project name says "Alpha" — projectId wins
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["projectId": beta.id.uuidString, "project": "Alpha"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "B1")
    }

    @Test func queryWithEmptyProjectNameReturnsAllTasks() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        _ = try await env.taskService.createTask(name: "A", description: nil, type: .feature, project: project)
        _ = try await env.taskService.createTask(name: "B", description: nil, type: .bug, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "  "]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 2)
    }

    @Test func queryByProjectNameCombinedWithStatusFilter() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        let task = try await env.taskService.createTask(
            name: "Planned", description: nil, type: .feature, project: project
        )
        try env.taskService.updateStatus(task: task, to: .planning)
        _ = try await env.taskService.createTask(name: "Idea", description: nil, type: .bug, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "Alpha", "status": "planning"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Planned")
    }

    @Test func queryByAmbiguousProjectNameReturnsError() async throws {
        let env = try MCPTestHelpers.makeEnv()
        // Insert duplicates directly to simulate pre-existing data (e.g. from CloudKit sync).
        let first = Project(name: "Alpha", description: "", gitRepo: nil, colorHex: "#000000")
        let second = Project(name: "alpha", description: "", gitRepo: nil, colorHex: "#111111")
        env.context.insert(first)
        env.context.insert(second)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "Alpha"]
        ))

        #expect(try MCPTestHelpers.isError(response))
    }

    @Test func queryByProjectNameCombinedWithTypeFilter() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        _ = try await env.taskService.createTask(name: "Bug", description: nil, type: .bug, project: project)
        _ = try await env.taskService.createTask(name: "Feature", description: nil, type: .feature, project: project)

        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["project": "Alpha", "type": "bug"]
        ))

        let results = try MCPTestHelpers.decodeArrayResult(response)
        #expect(results.count == 1)
        #expect(results.first?["name"] as? String == "Bug")
    }
}

#endif
