import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-754: Query intents must reject invalid enum filter values
/// (status, type) with explicit errors instead of silently returning empty/full results.
@MainActor @Suite(.serialized)
struct QueryIntentEnumValidationTests {

    // MARK: - Helpers

    private struct TaskServices {
        let task: TaskService
        let project: ProjectService
        let context: ModelContext
    }

    private struct MilestoneServices {
        let milestone: MilestoneService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeTaskServices() throws -> TaskServices {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return TaskServices(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            context: context
        )
    }

    private func makeMilestoneServices() throws -> MilestoneServices {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return MilestoneServices(
            milestone: MilestoneService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            context: context
        )
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - QueryTasksIntent: Invalid status

    @Test func queryTasksWithInvalidStatusReturnsError() throws {
        // T-754: Passing an invalid status should return INVALID_STATUS, not silently filter
        let svc = try makeTaskServices()

        let result = QueryTasksIntent.execute(
            input: "{\"status\":\"not-a-status\"}",
            projectService: svc.project,
            taskService: svc.task
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
    }

    @Test func queryTasksWithInvalidTypeReturnsError() throws {
        // T-754: Passing an invalid type should return INVALID_TYPE, not silently filter
        let svc = try makeTaskServices()

        let result = QueryTasksIntent.execute(
            input: "{\"type\":\"not-a-type\"}",
            projectService: svc.project,
            taskService: svc.task
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_TYPE")
    }

    @Test func queryTasksWithValidStatusStillWorks() throws {
        // Ensure valid enum values continue to work after adding validation
        let svc = try makeTaskServices()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        svc.context.insert(project)
        let task = TransitTask(name: "T", type: .bug, project: project, displayID: .permanent(1))
        StatusEngine.initializeNewTask(task)
        svc.context.insert(task)

        let result = QueryTasksIntent.execute(
            input: "{\"status\":\"idea\"}",
            projectService: svc.project,
            taskService: svc.task
        )

        // Should return an array, not an error
        let data = try #require(result.data(using: .utf8))
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(array.count == 1)
    }

    @Test func queryTasksWithValidTypeStillWorks() throws {
        // Ensure valid enum values continue to work after adding validation
        let svc = try makeTaskServices()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        svc.context.insert(project)
        let task = TransitTask(name: "T", type: .bug, project: project, displayID: .permanent(1))
        StatusEngine.initializeNewTask(task)
        svc.context.insert(task)

        let result = QueryTasksIntent.execute(
            input: "{\"type\":\"bug\"}",
            projectService: svc.project,
            taskService: svc.task
        )

        let data = try #require(result.data(using: .utf8))
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(array.count == 1)
    }

    // MARK: - QueryMilestonesIntent: Invalid status

    @Test func queryMilestonesWithInvalidStatusReturnsError() throws {
        // T-754: Passing an invalid status should return INVALID_STATUS, not silently filter
        let svc = try makeMilestoneServices()

        let result = QueryMilestonesIntent.execute(
            input: "{\"status\":\"not-a-status\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
    }

    @Test func queryMilestonesWithValidStatusStillWorks() throws {
        // Ensure valid enum values continue to work after adding validation
        let svc = try makeMilestoneServices()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        svc.context.insert(project)
        let milestone = Milestone(name: "v1", description: nil, project: project, displayID: .permanent(1))
        svc.context.insert(milestone)

        let result = QueryMilestonesIntent.execute(
            input: "{\"status\":\"open\"}",
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let data = try #require(result.data(using: .utf8))
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(array.count == 1)
    }
}
