#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-1824: both milestone-query surfaces must resolve a syntactically valid
/// projectId through ProjectService before either the full or display-ID query path.
@MainActor @Suite(.serialized)
struct QueryMilestonesProjectIDResolutionTests {

    private struct FetchFailure: Swift.Error, CustomStringConvertible {
        var description: String { "simulated project fetch failure" }
    }

    private struct FailingProjectFetcher: ModelFetching {
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            throw FetchFailure()
        }
    }

    private func input(from arguments: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: arguments)
        return try #require(String(data: data, encoding: .utf8))
    }

    private func intentError(_ response: String) throws -> [String: Any] {
        let data = try #require(response.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func intentArray(_ response: String) throws -> [[String: Any]] {
        let data = try #require(response.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test func missingProjectIdReturnsExactNotFoundAcrossFullAndDisplayIDQueries() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let milestone = try await env.milestoneService.createMilestone(
            name: "Release", description: nil, project: project
        )
        let missingProjectID = UUID()
        let expectedHint = "No project with ID \(missingProjectID.uuidString)"

        for displayId in [Int?.none, milestone.permanentDisplayId] {
            var arguments: [String: Any] = ["projectId": missingProjectID.uuidString]
            if let displayId {
                arguments["displayId"] = displayId
            }

            let mcpResponse = await env.handler.handle(MCPTestHelpers.toolCallRequest(
                tool: "query_milestones", arguments: arguments
            ))
            #expect(try MCPTestHelpers.isError(mcpResponse))
            #expect(try MCPTestHelpers.errorText(mcpResponse) == expectedHint)

            let intentResponse = QueryMilestonesIntent.execute(
                input: try input(from: arguments),
                milestoneService: env.milestoneService,
                projectService: env.projectService
            )
            let intentError = try intentError(intentResponse)
            #expect(intentError["error"] as? String == "PROJECT_NOT_FOUND")
            #expect(intentError["hint"] as? String == expectedHint)
        }
    }

    @Test func projectIdSyntaxAndNamePrecedenceAreConsistentAcrossFullAndDisplayIDQueries() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let target = MCPTestHelpers.makeProject(in: env.context, name: "Target")
        let decoy = MCPTestHelpers.makeProject(in: env.context, name: "Decoy")
        let targetMilestone = try await env.milestoneService.createMilestone(
            name: "Target Release", description: nil, project: target
        )
        _ = try await env.milestoneService.createMilestone(
            name: "Decoy Release", description: nil, project: decoy
        )

        for displayId in [Int?.none, targetMilestone.permanentDisplayId] {
            var arguments: [String: Any] = [
                "projectId": target.id.uuidString,
                "project": "Decoy"
            ]
            if let displayId {
                arguments["displayId"] = displayId
            }

            let mcpResponse = await env.handler.handle(MCPTestHelpers.toolCallRequest(
                tool: "query_milestones", arguments: arguments
            ))
            let mcpResults = try MCPTestHelpers.decodeArrayResult(mcpResponse)
            #expect(mcpResults.count == 1)
            #expect(mcpResults.first?["name"] as? String == "Target Release")

            let intentResponse = QueryMilestonesIntent.execute(
                input: try input(from: arguments),
                milestoneService: env.milestoneService,
                projectService: env.projectService
            )
            let intentResults = try intentArray(intentResponse)
            #expect(intentResults.count == 1)
            #expect(intentResults.first?["name"] as? String == "Target Release")
        }

        let malformedArguments: [String: Any] = [
            "projectId": "not-a-uuid",
            "project": "Target"
        ]
        let mcpResponse = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones", arguments: malformedArguments
        ))
        #expect(try MCPTestHelpers.isError(mcpResponse))
        #expect(try MCPTestHelpers.errorText(mcpResponse) == "Invalid projectId: expected a UUID string")

        let intentResponse = QueryMilestonesIntent.execute(
            input: try input(from: malformedArguments),
            milestoneService: env.milestoneService,
            projectService: env.projectService
        )
        let intentError = try intentError(intentResponse)
        #expect(intentError["error"] as? String == "INVALID_INPUT")
    }

    @Test func projectLookupStorageFailureReturnsExactErrorsAcrossFullAndDisplayIDQueries() async throws {
        let env = try MCPTestHelpers.makeEnv(projectFetcher: FailingProjectFetcher())
        let projectID = UUID()
        let expectedHint = "Failed to fetch project: simulated project fetch failure"

        for displayId in [Int?.none, 1] {
            var arguments: [String: Any] = ["projectId": projectID.uuidString]
            if let displayId {
                arguments["displayId"] = displayId
            }

            let mcpResponse = await env.handler.handle(MCPTestHelpers.toolCallRequest(
                tool: "query_milestones", arguments: arguments
            ))
            #expect(try MCPTestHelpers.isError(mcpResponse))
            #expect(try MCPTestHelpers.errorText(mcpResponse) == expectedHint)

            let intentResponse = QueryMilestonesIntent.execute(
                input: try input(from: arguments),
                milestoneService: env.milestoneService,
                projectService: env.projectService
            )
            let intentError = try intentError(intentResponse)
            #expect(intentError["error"] as? String == "INTERNAL_ERROR")
            #expect(intentError["hint"] as? String == expectedHint)
        }
    }
}
#endif
