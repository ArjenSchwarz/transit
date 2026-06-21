import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1566: the JSON App Intent query paths must surface storage
/// fetch failures as an INTERNAL_ERROR payload rather than silently returning an empty
/// array, which a caller cannot distinguish from a valid "no results" query.
@MainActor @Suite(.serialized)
struct QueryIntentFetchFailureTests {

    // MARK: - Failing fetch seams

    private struct FetchFailure: Swift.Error {}

    /// A `TaskFetching` whose full-table fetch always fails, simulating a SwiftData error.
    private struct FailingTaskFetcher: TaskFetching {
        func fetchAllTasks() throws -> [TransitTask] { throw FetchFailure() }
    }

    /// A `MilestoneFetching` whose full-table fetch always fails, simulating a SwiftData error.
    private struct FailingMilestoneFetcher: MilestoneFetching {
        func fetchAllMilestones() throws -> [Milestone] { throw FetchFailure() }
    }

    // MARK: - Service setup

    private struct Services {
        let task: TaskService
        let project: ProjectService
        let milestone: MilestoneService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: allocator),
            context: context
        )
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    // MARK: - QueryTasksIntent

    @Test func taskFetchFailureReturnsInternalErrorNotEmptyArray() throws {
        let svc = try makeServices()

        let result = QueryTasksIntent.execute(
            input: "{}",
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone,
            taskFetcher: FailingTaskFetcher()
        )

        // Expected: an INTERNAL_ERROR payload. Before the fix this was "[]" — a successful
        // empty array indistinguishable from a valid no-match query.
        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INTERNAL_ERROR")
        #expect((parsed["hint"] as? String)?.isEmpty == false)
    }

    @Test func taskFetchSuccessWithNoMatchesStillReturnsEmptyArray() throws {
        let svc = try makeServices()

        // Real (working) fetcher over an empty store: a genuine empty result must remain
        // an empty array, so the error case stays distinguishable from "no matches".
        let result = QueryTasksIntent.execute(
            input: "{}",
            projectService: svc.project,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.isEmpty)
    }

    // MARK: - QueryMilestonesIntent

    @Test func milestoneFetchFailureReturnsInternalErrorNotEmptyArray() throws {
        let svc = try makeServices()

        let result = QueryMilestonesIntent.execute(
            input: "{}",
            milestoneService: svc.milestone,
            projectService: svc.project,
            milestoneFetcher: FailingMilestoneFetcher()
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INTERNAL_ERROR")
        #expect((parsed["hint"] as? String)?.isEmpty == false)
    }

    @Test func milestoneFetchSuccessWithNoMatchesStillReturnsEmptyArray() throws {
        let svc = try makeServices()

        let result = QueryMilestonesIntent.execute(
            input: "{}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.isEmpty)
    }
}
