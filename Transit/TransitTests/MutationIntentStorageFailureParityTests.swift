import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-1770 follow-up: shared milestone resolution used by task updates must preserve
/// typed not-found responses while mapping unreadable storage to INTERNAL_ERROR.
@MainActor @Suite(.serialized)
struct MutationIntentStorageFailureParityTests {

    private struct FetchFailure: Swift.Error, CustomStringConvertible {
        var description: String { "simulated milestone fetch failure" }
    }

    private struct FailingFetcher: ModelFetching {
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            throw FetchFailure()
        }
    }

    private func allocator() -> DisplayIDAllocator {
        DisplayIDAllocator(store: InMemoryCounterStore())
    }

    private func makeTask(in context: ModelContext, project: Project) -> TransitTask {
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(1))
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        return task
    }

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Transit", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        return project
    }

    private func expectInternalError(_ result: String, hint: String) throws {
        let data = try #require(result.data(using: .utf8))
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(payload.keys) == Set(["error", "hint"]))
        #expect(payload["error"] as? String == "INTERNAL_ERROR")
        #expect(payload["hint"] as? String == hint)
    }

    @Test func updateTaskReportsInternalErrorWhenMilestoneLookupFails() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let task = makeTask(in: context, project: project)
        try context.save()

        let result = UpdateTaskIntent.execute(
            input: "{\"displayId\":1,\"milestoneDisplayId\":1}",
            taskService: TaskService(modelContext: context, displayIDAllocator: allocator()),
            milestoneService: MilestoneService(
                modelContext: context, displayIDAllocator: allocator(), fetcher: FailingFetcher()
            )
        )

        try expectInternalError(result, hint: "Failed to look up milestone: simulated milestone fetch failure")
        #expect(task.milestone == nil)
    }

    @Test func sharedMilestoneAssignmentReportsInternalErrorWhenLookupFails() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let task = makeTask(in: context, project: project)
        try context.save()

        let result = IntentHelpers.assignMilestone(
            from: ["milestoneDisplayId": 1],
            to: task,
            milestoneService: MilestoneService(
                modelContext: context, displayIDAllocator: allocator(), fetcher: FailingFetcher()
            )
        )

        try expectInternalError(try #require(result), hint: "Failed to assign milestone")
        #expect(task.milestone == nil)
    }
}
