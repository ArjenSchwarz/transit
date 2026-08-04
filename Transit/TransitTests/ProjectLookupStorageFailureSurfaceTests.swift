import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-1657: every project-lookup caller must distinguish an unreadable store from a
/// missing project. JSON surfaces use INTERNAL_ERROR, MCP uses a tool error, and the
/// visual intent's code must likewise identify storage failure. None may insert data.
@MainActor @Suite(.serialized)
struct ProjectLookupStorageFailureSurfaceTests {

    private struct FetchFailure: Swift.Error, CustomStringConvertible {
        var description: String { "simulated project fetch failure" }
    }

    private struct FailingProjectFetcher: ModelFetching {
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            throw FetchFailure()
        }
    }

    private func allocator() -> DisplayIDAllocator {
        DisplayIDAllocator(store: InMemoryCounterStore())
    }

    private func expectInternalError(_ result: String, hint: String) throws {
        let data = try #require(result.data(using: .utf8))
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(payload.keys) == Set(["error", "hint"]))
        #expect(payload["error"] as? String == "INTERNAL_ERROR")
        #expect(payload["hint"] as? String == hint)
    }

    @Test func jsonCreatePathsReturnInternalErrorWithoutInsertionWhenProjectLookupFails() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let projectService = ProjectService(modelContext: context, fetcher: FailingProjectFetcher())
        let projectID = UUID()

        let taskResult = await CreateTaskIntent.execute(
            input: "{\"projectId\":\"\(projectID.uuidString)\",\"name\":\"Task\",\"type\":\"feature\"}",
            taskService: TaskService(modelContext: context, displayIDAllocator: allocator()),
            projectService: projectService
        )
        let milestoneResult = await CreateMilestoneIntent.execute(
            input: "{\"projectId\":\"\(projectID.uuidString)\",\"name\":\"Milestone\"}",
            milestoneService: MilestoneService(modelContext: context, displayIDAllocator: allocator()),
            projectService: projectService
        )

        try expectInternalError(taskResult, hint: "Failed to fetch project: simulated project fetch failure")
        try expectInternalError(milestoneResult, hint: "Failed to fetch project: simulated project fetch failure")
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Milestone>()).isEmpty)
    }

    @Test func jsonQueryPathsReturnInternalErrorInsteadOfEmptyResultsWhenProjectLookupFails() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let projectService = ProjectService(modelContext: context, fetcher: FailingProjectFetcher())

        let taskResult = QueryTasksIntent.execute(
            input: "{\"projectId\":\"\(UUID().uuidString)\"}",
            projectService: projectService,
            taskService: TaskService(modelContext: context, displayIDAllocator: allocator()),
            milestoneService: MilestoneService(modelContext: context, displayIDAllocator: allocator())
        )
        let milestoneResult = QueryMilestonesIntent.execute(
            input: "{\"project\":\"Transit\"}",
            milestoneService: MilestoneService(modelContext: context, displayIDAllocator: allocator()),
            projectService: projectService
        )

        try expectInternalError(taskResult, hint: "Failed to fetch project: simulated project fetch failure")
        try expectInternalError(milestoneResult, hint: "Failed to fetch projects: simulated project fetch failure")
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Milestone>()).isEmpty)
    }

#if os(macOS)
    @Test func mcpCreateAndQueryPathsReturnStorageErrorsWithoutInsertionWhenProjectLookupFails() async throws {
        let env = try MCPTestHelpers.makeEnv(projectFetcher: FailingProjectFetcher())
        let projectID = UUID().uuidString

        let createTask = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: ["projectId": projectID, "name": "Task", "type": "feature"]
        ))
        let queryTasks = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks",
            arguments: ["projectId": projectID]
        ))
        let createMilestone = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "create_milestone",
            arguments: ["projectId": projectID, "name": "Milestone"]
        ))
        let queryMilestones = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_milestones",
            arguments: ["project": "Transit"]
        ))

        for response in [createTask, queryTasks, createMilestone, queryMilestones] {
            #expect(try MCPTestHelpers.isError(response))
        }
        let idLookupFailure = "Failed to fetch project: simulated project fetch failure"
        let nameLookupFailure = "Failed to fetch projects: simulated project fetch failure"
        #expect(try MCPTestHelpers.errorText(createTask) == idLookupFailure)
        #expect(try MCPTestHelpers.errorText(queryTasks) == idLookupFailure)
        #expect(try MCPTestHelpers.errorText(createMilestone) == idLookupFailure)
        #expect(try MCPTestHelpers.errorText(queryMilestones) == nameLookupFailure)
        #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
        #expect(try env.context.fetch(FetchDescriptor<Milestone>()).isEmpty)
    }
#endif

    @Test func visualAddTaskReportsInternalStorageErrorWithoutInsertionWhenProjectLookupFails() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator())
        let projectService = ProjectService(modelContext: context, fetcher: FailingProjectFetcher())
        let project = ProjectEntity(id: UUID().uuidString, projectId: UUID(), name: "Transit")

        do {
            _ = try await AddTaskIntent.execute(
                name: "Task",
                taskDescription: nil,
                type: .feature,
                project: project,
                services: AddTaskIntent.Services(taskService: taskService, projectService: projectService)
            )
            Issue.record("Expected project storage failure")
        } catch let error as VisualIntentError {
            #expect(error.code == "INTERNAL_ERROR")
            #expect(error.errorDescription == "Storage error: Failed to fetch project: simulated project fetch failure")
        }

        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }

    // T-1749: an unreadable project table must remain a storage error even when
    // Shortcuts has no selected project. It must not be reported as NO_PROJECTS.
    @Test func visualAddTaskReportsStorageFailureWhenProjectExistenceFetchFails() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator())
        let projectService = ProjectService(modelContext: context, fetcher: FailingProjectFetcher())

        do {
            _ = try await AddTaskIntent.execute(
                name: "Task",
                taskDescription: nil,
                type: .feature,
                project: nil,
                services: AddTaskIntent.Services(taskService: taskService, projectService: projectService)
            )
            Issue.record("Expected project existence storage failure")
        } catch let error as VisualIntentError {
            #expect(error == .storageFailure("Failed to fetch projects: simulated project fetch failure"))
            #expect(error.code == "INTERNAL_ERROR")
        }

        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }
}
