import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1836: while `ContainerFactory` is serving the in-memory fallback
/// container, mutating App Intents must reject the request instead of reporting success for a
/// write that disappears on the next launch. Shortcuts/CLI callers never see the app's
/// degraded-storage alert, so a plain success response is indistinguishable from durable
/// persistence.
///
/// The signal under test is derived from a real `ContainerFactory` failure via
/// `FallbackOutcomeFixture`, exactly as `TransitApp.init()` does at launch. Data assertions run
/// against isolated `TestModelContainer` contexts — see the fixture for why the fallback
/// container itself must not be used as a test store.
@MainActor
@Suite(.serialized)
struct FallbackStorageIntentRejectionTests {

    // MARK: - Helpers

    private struct Env {
        let context: ModelContext
        let persistence: PersistenceAvailability
        let taskService: TaskService
        let projectService: ProjectService
        let commentService: CommentService
        let milestoneService: MilestoneService
        let maintenanceService: DisplayIDMaintenanceService
    }

    /// Builds services on an isolated context, with `persistence` derived from a real
    /// `ContainerFactory` outcome. Pass `failPrimaryStore: false` for the healthy-storage baseline.
    private func makeEnv(failPrimaryStore: Bool = true) throws -> Env {
        let persistence = failPrimaryStore
            ? FallbackOutcomeFixture.degraded
            : FallbackOutcomeFixture.makeHealthy()

        let testContainer = try TestModelContainer()

        let context = testContainer.context
        let taskAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let commentService = CommentService(modelContext: context)
        return Env(
            context: context,
            persistence: persistence,
            taskService: TaskService(modelContext: context, displayIDAllocator: taskAllocator),
            projectService: ProjectService(modelContext: context),
            commentService: commentService,
            milestoneService: MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator),
            maintenanceService: DisplayIDMaintenanceService(
                modelContext: context,
                taskAllocator: taskAllocator,
                milestoneAllocator: milestoneAllocator,
                commentService: commentService
            )
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String = "Fallback Project") -> Project {
        let project = Project(name: name, description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeTask(in context: ModelContext, project: Project, displayID: Int = 1) -> TransitTask {
        let task = TransitTask(
            name: "Seeded Task", type: .bug, project: project, displayID: .permanent(displayID)
        )
        context.insert(task)
        return task
    }

    @discardableResult
    private func makeMilestone(in context: ModelContext, project: Project, displayID: Int = 1) -> Milestone {
        let milestone = Milestone(name: "Seeded Milestone", project: project, displayID: .permanent(displayID))
        context.insert(milestone)
        return milestone
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Asserts the intent returned the documented INTERNAL_ERROR envelope for degraded storage.
    private func expectRejected(_ result: String) throws {
        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INTERNAL_ERROR")
        #expect(parsed["hint"] as? String == PersistenceAvailability.unavailableHint)
    }

    // MARK: - Signal Derivation

    @Test("A failed ContainerFactory attempt marks persistence as unavailable")
    func fallbackOutcomeMarksUnavailable() {
        #expect(FallbackOutcomeFixture.degraded.isFallbackStorageActive)
    }

    @Test("A successful ContainerFactory attempt leaves persistence available")
    func healthyOutcomeStaysAvailable() {
        #expect(FallbackOutcomeFixture.makeHealthy().isFallbackStorageActive == false)
    }

    // MARK: - Create

    @Test("CreateTaskIntent is rejected while fallback storage is active")
    func createTaskRejected() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)

        let result = await CreateTaskIntent.execute(
            input: #"{"projectId":"\#(project.id.uuidString)","name":"Doomed","type":"bug"}"#,
            taskService: env.taskService,
            projectService: env.projectService,
            milestoneService: env.milestoneService,
            persistence: env.persistence
        )

        try expectRejected(result)
        // Nothing must be written — not even a provisional record.
        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.isEmpty)
    }

    @Test("CreateTaskIntent still succeeds when storage is durable")
    func createTaskAllowedWhenDurable() async throws {
        let env = try makeEnv(failPrimaryStore: false)
        let project = makeProject(in: env.context)

        let result = await CreateTaskIntent.execute(
            input: #"{"projectId":"\#(project.id.uuidString)","name":"Fine","type":"bug"}"#,
            taskService: env.taskService,
            projectService: env.projectService,
            milestoneService: env.milestoneService,
            persistence: env.persistence
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] is String)
        #expect(parsed["error"] == nil)
    }

    @Test("CreateMilestoneIntent is rejected while fallback storage is active")
    func createMilestoneRejected() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)

        let result = await CreateMilestoneIntent.execute(
            input: #"{"projectId":"\#(project.id.uuidString)","name":"Doomed Milestone"}"#,
            milestoneService: env.milestoneService,
            projectService: env.projectService,
            persistence: env.persistence
        )

        try expectRejected(result)
        #expect(try env.context.fetch(FetchDescriptor<Milestone>()).isEmpty)
    }

    @Test("Visual AddTaskIntent throws while fallback storage is active")
    func visualAddTaskRejected() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)

        await #expect(throws: VisualIntentError.persistenceUnavailable) {
            try await AddTaskIntent.execute(
                name: "Doomed",
                taskDescription: nil,
                type: .bug,
                project: ProjectEntity.from(project),
                services: AddTaskIntent.Services(
                    taskService: env.taskService, projectService: env.projectService
                ),
                persistence: env.persistence
            )
        }
        #expect(try env.context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }

    // MARK: - Update

    @Test("UpdateStatusIntent is rejected while fallback storage is active")
    func updateStatusRejected() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        let task = makeTask(in: env.context, project: project)

        let result = UpdateStatusIntent.execute(
            input: #"{"displayId":1,"status":"in-progress"}"#,
            taskService: env.taskService,
            persistence: env.persistence
        )

        try expectRejected(result)
        #expect(task.statusRawValue == TaskStatus.idea.rawValue)
    }

    @Test("UpdateTaskIntent is rejected while fallback storage is active")
    func updateTaskRejected() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        let task = makeTask(in: env.context, project: project)

        let result = UpdateTaskIntent.execute(
            input: #"{"displayId":1,"priority":"high"}"#,
            taskService: env.taskService,
            milestoneService: env.milestoneService,
            persistence: env.persistence
        )

        try expectRejected(result)
        #expect(task.priority == .medium)
    }

    @Test("UpdateMilestoneIntent is rejected while fallback storage is active")
    func updateMilestoneRejected() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        let milestone = makeMilestone(in: env.context, project: project)

        let result = UpdateMilestoneIntent.execute(
            input: #"{"displayId":1,"status":"done"}"#,
            milestoneService: env.milestoneService,
            projectService: env.projectService,
            persistence: env.persistence
        )

        try expectRejected(result)
        #expect(milestone.statusRawValue == MilestoneStatus.open.rawValue)
    }

    // MARK: - Delete

    @Test("DeleteMilestoneIntent is rejected while fallback storage is active")
    func deleteMilestoneRejected() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        makeMilestone(in: env.context, project: project)

        let result = DeleteMilestoneIntent.execute(
            input: #"{"displayId":1}"#,
            milestoneService: env.milestoneService,
            persistence: env.persistence
        )

        try expectRejected(result)
        #expect(try env.context.fetch(FetchDescriptor<Milestone>()).count == 1)
    }

    // MARK: - Comment

    @Test("AddCommentIntent throws while fallback storage is active")
    func addCommentRejected() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        makeTask(in: env.context, project: project)

        #expect(throws: VisualIntentError.persistenceUnavailable) {
            try AddCommentIntent.execute(
                taskIdentifier: "1",
                commentText: "Doomed comment",
                authorName: "Agent",
                isAgent: true,
                services: AddCommentIntent.Services(
                    taskService: env.taskService, commentService: env.commentService
                ),
                persistence: env.persistence
            )
        }
        // Module-qualified: Swift Testing also exports a `Comment` type.
        #expect(try env.context.fetch(FetchDescriptor<Transit.Comment>()).isEmpty)
    }

    // MARK: - Maintenance

    @Test("ReassignDuplicateDisplayIDsIntent is rejected while fallback storage is active")
    func reassignDuplicatesRejected() async throws {
        let env = try makeEnv()

        let result = await ReassignDuplicateDisplayIDsIntent.execute(
            maintenanceService: env.maintenanceService,
            persistence: env.persistence
        )

        try expectRejected(result)
    }

    // MARK: - Reads Stay Available

    @Test("Read intents keep working while fallback storage is active")
    func readIntentsStillWork() async throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        makeTask(in: env.context, project: project)

        let tasks = QueryTasksIntent.execute(
            input: "{}",
            projectService: env.projectService,
            taskService: env.taskService,
            milestoneService: env.milestoneService
        )
        #expect(tasks.contains("Seeded Task"))

        let scan = await ScanDuplicateDisplayIDsIntent.execute(maintenanceService: env.maintenanceService)
        let parsedScan = try parseJSON(scan)
        #expect(parsedScan["error"] == nil)
    }
}
