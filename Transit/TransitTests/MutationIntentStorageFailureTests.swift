import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-1770: A failed storage read is not a caller error. These tests inject a
/// fetcher that fails while the backing context remains writable, then assert
/// every affected JSON mutation intent returns INTERNAL_ERROR without mutation.
@MainActor @Suite(.serialized)
struct MutationIntentStorageFailureTests {

    private struct FetchFailure: Swift.Error {}

    private struct FailingFetcher: ModelFetching {
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            throw FetchFailure()
        }
    }

    private func allocator() -> DisplayIDAllocator {
        DisplayIDAllocator(store: InMemoryCounterStore())
    }

    @discardableResult
    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Transit", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeMilestone(
        in context: ModelContext, project: Project, displayID: Int = 1
    ) -> Milestone {
        let milestone = Milestone(name: "Beta", description: nil, project: project, displayID: .permanent(displayID))
        context.insert(milestone)
        return milestone
    }

    @discardableResult
    private func makeTask(
        in context: ModelContext, project: Project, displayID: Int = 1
    ) -> TransitTask {
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(displayID))
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        return task
    }

    private func expectInternalError(_ result: String) throws {
        let data = try #require(result.data(using: .utf8))
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(payload.keys) == Set(["error", "hint"]))
        #expect(payload["error"] as? String == "INTERNAL_ERROR")
    }

    @Test func createTaskReportsInternalErrorWhenMilestoneLookupFails() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        makeMilestone(in: context, project: project)
        try context.save()

        let result = await CreateTaskIntent.execute(
            input: """
            {"projectId":"\(project.id.uuidString)","name":"New task","type":"feature","milestoneDisplayId":1}
            """,
            taskService: TaskService(modelContext: context, displayIDAllocator: allocator()),
            projectService: ProjectService(modelContext: context),
            milestoneService: MilestoneService(
                modelContext: context, displayIDAllocator: allocator(), fetcher: FailingFetcher()
            )
        )

        try expectInternalError(result)
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }

    @Test func createMilestoneReportsInternalErrorWhenUniquenessFetchFails() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        try context.save()

        let result = await CreateMilestoneIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\",\"name\":\"Beta\"}",
            milestoneService: MilestoneService(
                modelContext: context, displayIDAllocator: allocator(), fetcher: FailingFetcher()
            ),
            projectService: ProjectService(modelContext: context)
        )

        try expectInternalError(result)
        #expect(try context.fetch(FetchDescriptor<Milestone>()).isEmpty)
    }

    @Test func updateStatusReportsInternalErrorWhenTaskLookupFails() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let task = makeTask(in: context, project: project)
        try context.save()

        let result = UpdateStatusIntent.execute(
            input: "{\"displayId\":1,\"status\":\"planning\"}",
            taskService: TaskService(
                modelContext: context, displayIDAllocator: allocator(), fetcher: FailingFetcher()
            )
        )

        try expectInternalError(result)
        #expect(task.status == .idea)
    }

    @Test func updateMilestoneReportsInternalErrorWhenMilestoneLookupFails() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let milestone = makeMilestone(in: context, project: project)
        try context.save()

        let result = UpdateMilestoneIntent.execute(
            input: "{\"displayId\":1,\"status\":\"done\"}",
            milestoneService: MilestoneService(
                modelContext: context, displayIDAllocator: allocator(), fetcher: FailingFetcher()
            ),
            projectService: ProjectService(modelContext: context)
        )

        try expectInternalError(result)
        #expect(milestone.status == .open)
    }

    @Test func deleteMilestoneReportsInternalErrorWhenMilestoneLookupFails() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let milestone = makeMilestone(in: context, project: project)
        try context.save()

        let result = DeleteMilestoneIntent.execute(
            input: "{\"displayId\":1}",
            milestoneService: MilestoneService(
                modelContext: context, displayIDAllocator: allocator(), fetcher: FailingFetcher()
            )
        )

        try expectInternalError(result)
        #expect(try context.fetch(FetchDescriptor<Milestone>()).map(\.id) == [milestone.id])
    }
}

extension MutationIntentStorageFailureTests {

    @Test func createTaskReportsInternalErrorAndDeletesPendingTaskWhenSaveFails() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        try context.save()

        let result = await CreateTaskIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\",\"name\":\"New task\",\"type\":\"feature\"}",
            taskService: TaskService(
                modelContext: context,
                displayIDAllocator: allocator(),
                createSave: { _ in throw SaveFailure.simulated }
            ),
            projectService: ProjectService(modelContext: context)
        )

        try expectInternalError(result)
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }

    @Test func createMilestoneReportsInternalErrorAndDeletesPendingMilestoneWhenSaveFails() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        try context.save()

        let result = await CreateMilestoneIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\",\"name\":\"Beta\"}",
            milestoneService: MilestoneService(
                modelContext: context,
                displayIDAllocator: allocator(),
                mutationSave: { _ in throw SaveFailure.simulated }
            ),
            projectService: ProjectService(modelContext: context)
        )

        try expectInternalError(result)
        #expect(try context.fetch(FetchDescriptor<Milestone>()).isEmpty)
    }

    @Test func updateStatusReportsInternalErrorAndRollsBackWhenSaveFails() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let task = makeTask(in: context, project: project)
        try context.save()

        let result = UpdateStatusIntent.execute(
            input: "{\"displayId\":1,\"status\":\"planning\"}",
            taskService: TaskService(
                modelContext: context,
                displayIDAllocator: allocator(),
                statusSave: { _ in throw SaveFailure.simulated }
            )
        )

        try expectInternalError(result)
        #expect(task.status == .idea)
    }

    @Test func updateMilestoneReportsInternalErrorAndRollsBackWhenSaveFails() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let milestone = makeMilestone(in: context, project: project)
        try context.save()

        let result = UpdateMilestoneIntent.execute(
            input: "{\"displayId\":1,\"status\":\"done\"}",
            milestoneService: MilestoneService(
                modelContext: context,
                displayIDAllocator: allocator(),
                mutationSave: { _ in throw SaveFailure.simulated }
            ),
            projectService: ProjectService(modelContext: context)
        )

        try expectInternalError(result)
        #expect(milestone.status == .open)
    }

    @Test func deleteMilestoneReportsInternalErrorAndRollsBackWhenSaveFails() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = makeProject(in: context)
        let milestone = makeMilestone(in: context, project: project)
        try context.save()

        let result = DeleteMilestoneIntent.execute(
            input: "{\"displayId\":1}",
            milestoneService: MilestoneService(
                modelContext: context,
                displayIDAllocator: allocator(),
                mutationSave: { _ in throw SaveFailure.simulated }
            )
        )

        try expectInternalError(result)
        #expect(try context.fetch(FetchDescriptor<Milestone>()).map(\.id) == [milestone.id])
    }
}
