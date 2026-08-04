#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-1675: a failed project-scoped milestone name lookup must stay distinct from
/// a genuine no-match. JSON surfaces return the exact INTERNAL_ERROR envelope;
/// MCP returns the exact tool error; no create or update may mutate data.
@MainActor @Suite(.serialized)
struct MilestoneNameLookupFailureTests {

    private struct FetchFailure: Swift.Error, CustomStringConvertible {
        var description: String { "simulated milestone name lookup fetch failure" }
    }

    private struct FailingMilestoneFetcher: ModelFetching {
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            throw FetchFailure()
        }
    }

    private func allocator() -> DisplayIDAllocator {
        DisplayIDAllocator(store: InMemoryCounterStore())
    }

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Transit", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        return project
    }

    private func makeTask(in context: ModelContext, project: Project) -> TransitTask {
        let task = TransitTask(name: "Existing", type: .feature, project: project, displayID: .permanent(1))
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        return task
    }

    private func makeMilestone(in context: ModelContext, project: Project) -> Milestone {
        let milestone = Milestone(name: "Sprint", description: nil, project: project, displayID: .permanent(1))
        context.insert(milestone)
        return milestone
    }

    private func expectInternalError(_ result: String, hint: String) throws {
        let data = try #require(result.data(using: .utf8))
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(payload.keys) == Set(["error", "hint"]))
        #expect(payload["error"] as? String == "INTERNAL_ERROR")
        #expect(payload["hint"] as? String == hint)
    }

    @Test func findByNamePropagatesInjectedFetchFailureInsteadOfReturningNoMatch() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let service = MilestoneService(
            modelContext: context,
            displayIDAllocator: allocator(),
            fetcher: FailingMilestoneFetcher()
        )

        do {
            _ = try service.findByName("Sprint", in: project)
            Issue.record("Expected the injected milestone fetch to fail")
        } catch {
            #expect(String(describing: error) == "simulated milestone name lookup fetch failure")
        }
    }

    @Test func jsonCreateAndUpdatePathsReturnExactLookupErrorWithoutMutation() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let task = makeTask(in: context, project: project)
        let milestone = makeMilestone(in: context, project: project)
        try context.save()

        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator())
        let projectService = ProjectService(modelContext: context)
        let milestoneService = MilestoneService(
            modelContext: context,
            displayIDAllocator: allocator(),
            fetcher: FailingMilestoneFetcher()
        )
        let expectedHint = "Failed to look up milestone: simulated milestone name lookup fetch failure"

        let createResult = await CreateTaskIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\",\"name\":\"New\","
                + "\"type\":\"feature\",\"milestone\":\"Sprint\"}",
            taskService: taskService,
            projectService: projectService,
            milestoneService: milestoneService
        )
        let updateTaskResult = UpdateTaskIntent.execute(
            input: "{\"displayId\":1,\"milestone\":\"Sprint\"}",
            taskService: taskService,
            milestoneService: milestoneService
        )
        let updateMilestoneResult = UpdateMilestoneIntent.execute(
            input: "{\"name\":\"Sprint\",\"projectId\":\"\(project.id.uuidString)\",\"description\":\"Changed\"}",
            milestoneService: milestoneService,
            projectService: projectService
        )
        let assignmentResult = IntentHelpers.assignMilestone(
            from: ["milestone": "Sprint"], to: task, milestoneService: milestoneService
        )

        try expectInternalError(createResult, hint: expectedHint)
        try expectInternalError(updateTaskResult, hint: expectedHint)
        try expectInternalError(updateMilestoneResult, hint: expectedHint)
        try expectInternalError(try #require(assignmentResult), hint: expectedHint)
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).count == 1)
        #expect(task.name == "Existing")
        #expect(task.milestone == nil)
        #expect(milestone.milestoneDescription == nil)
    }

    @Test func mcpCreateUpdateAndScopedQueryReturnExactLookupErrorWithoutMutation() async throws {
        let env = try MCPTestHelpers.makeEnv(milestoneServiceFetcher: FailingMilestoneFetcher())
        let project = MCPTestHelpers.makeProject(in: env.context, name: "Transit")
        let task = try await env.taskService.createTask(
            name: "Existing", description: nil, type: .feature, project: project
        )
        let taskDisplayId = try #require(task.permanentDisplayId)
        let expectedHint = "Failed to look up milestone: simulated milestone name lookup fetch failure"

        let createResponse = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["projectId": project.id.uuidString, "name": "New", "type": "feature", "milestone": "Sprint"]
        ))
        let updateResponse = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "update_task",
            arguments: ["displayId": taskDisplayId, "milestone": "Sprint"]
        ))
        let queryResponse = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["projectId": project.id.uuidString, "milestone": "Sprint"]
        ))

        for response in [createResponse, updateResponse, queryResponse] {
            #expect(try MCPTestHelpers.isError(response))
            #expect(try MCPTestHelpers.errorText(response) == expectedHint)
        }
        #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).count == 1)
        #expect(task.name == "Existing")
        #expect(task.milestone == nil)
    }
}
#endif
