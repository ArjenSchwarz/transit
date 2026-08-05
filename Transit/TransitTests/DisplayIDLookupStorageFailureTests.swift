#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-1862: single-record display-ID queries must preserve the three lookup
/// outcomes across their JSON and MCP adapters: not-found is `[]`, duplicate
/// IDs remain explicit errors, and storage failures remain INTERNAL_ERROR/tool
/// errors rather than false successful empty arrays.
@MainActor @Suite(.serialized)
struct DisplayIDLookupStorageFailureTests {

    private struct FetchFailure: Swift.Error, CustomStringConvertible {
        var description: String { "simulated display-ID lookup fetch failure" }
    }

    private struct FailingLookupFetcher: ModelFetching {
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            throw FetchFailure()
        }
    }

    private func allocator() -> DisplayIDAllocator {
        DisplayIDAllocator(store: InMemoryCounterStore())
    }

    private func intentArray(_ response: String) throws -> [[String: Any]] {
        let data = try #require(response.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private func expectIntentInternalError(_ response: String, hint: String) throws {
        let data = try #require(response.data(using: .utf8))
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(payload.keys) == Set(["error", "hint"]))
        #expect(payload["error"] as? String == "INTERNAL_ERROR")
        #expect(payload["hint"] as? String == hint)
    }

    @Test func queryTasksDisplayIdClassifiesNotFoundDuplicateAndStorageFailure() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let projectService = ProjectService(modelContext: context)
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: allocator())
        let normalTaskService = TaskService(modelContext: context, displayIDAllocator: allocator())

        let missing = QueryTasksIntent.execute(
            input: #"{"displayId":42}"#,
            projectService: projectService,
            taskService: normalTaskService,
            milestoneService: milestoneService
        )
        #expect(try intentArray(missing).isEmpty)

        let project = Project(name: "Transit", description: "", gitRepo: nil, colorHex: "#000000")
        let first = TransitTask(name: "First", type: .feature, project: project, displayID: .permanent(42))
        let second = TransitTask(name: "Second", type: .feature, project: project, displayID: .permanent(42))
        StatusEngine.initializeNewTask(first)
        StatusEngine.initializeNewTask(second)
        context.insert(project)
        context.insert(first)
        context.insert(second)

        let duplicate = QueryTasksIntent.execute(
            input: #"{"displayId":42}"#,
            projectService: projectService,
            taskService: normalTaskService,
            milestoneService: milestoneService
        )
        try expectIntentInternalError(
            duplicate,
            hint: "Duplicate task identifier for displayId 42"
        )

        let failingTaskService = TaskService(
            modelContext: context,
            displayIDAllocator: allocator(),
            fetcher: FailingLookupFetcher()
        )
        let storageFailure = QueryTasksIntent.execute(
            input: #"{"displayId":43}"#,
            projectService: projectService,
            taskService: failingTaskService,
            milestoneService: milestoneService
        )
        try expectIntentInternalError(
            storageFailure,
            hint: "Failed to look up task: simulated display-ID lookup fetch failure"
        )
    }

    @Test func queryMilestonesDisplayIdClassifiesOutcomesAcrossIntentAndMCP() async throws {
        let normal = try MCPTestHelpers.makeEnv()
        let missingArguments: [String: Any] = ["displayId": 42]

        let missingMCP = await normal.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones", arguments: missingArguments
        ))
        #expect(try MCPTestHelpers.decodeArrayResult(missingMCP).isEmpty)
        let missingIntent = QueryMilestonesIntent.execute(
            input: #"{"displayId":42}"#,
            milestoneService: normal.milestoneService,
            projectService: normal.projectService
        )
        #expect(try intentArray(missingIntent).isEmpty)

        let project = MCPTestHelpers.makeProject(in: normal.context, name: "Transit")
        let first = Milestone(name: "First", description: nil, project: project, displayID: .permanent(42))
        let second = Milestone(name: "Second", description: nil, project: project, displayID: .permanent(42))
        normal.context.insert(first)
        normal.context.insert(second)

        let duplicateMCP = await normal.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones", arguments: missingArguments
        ))
        #expect(try MCPTestHelpers.isError(duplicateMCP))
        #expect(try MCPTestHelpers.errorText(duplicateMCP)
            == "Duplicate milestone identifier detected for displayId 42")
        let duplicateIntent = QueryMilestonesIntent.execute(
            input: #"{"displayId":42}"#,
            milestoneService: normal.milestoneService,
            projectService: normal.projectService
        )
        try expectIntentInternalError(
            duplicateIntent,
            hint: "A duplicate milestone identifier was detected"
        )

        let failing = try MCPTestHelpers.makeEnv(milestoneServiceFetcher: FailingLookupFetcher())
        let storageFailureMCP = await failing.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones", arguments: missingArguments
        ))
        #expect(try MCPTestHelpers.isError(storageFailureMCP))
        #expect(try MCPTestHelpers.errorText(storageFailureMCP)
            == "Failed to look up milestone: simulated display-ID lookup fetch failure")
        let storageFailureIntent = QueryMilestonesIntent.execute(
            input: #"{"displayId":42}"#,
            milestoneService: failing.milestoneService,
            projectService: failing.projectService
        )
        try expectIntentInternalError(
            storageFailureIntent,
            hint: "Failed to look up milestone: simulated display-ID lookup fetch failure"
        )
    }
}
#endif
