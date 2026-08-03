import Foundation
import SwiftData
import Testing
@testable import Transit

// swiftlint:disable type_body_length

/// Regression coverage for T-1939. The fixture commits display ID 10, then
/// restores only the main context's registered value to 9 without saving. This
/// deterministically models a stale peer-merge snapshot while also proving that
/// live/pending registered IDs remain blocked by the combined collision set.
@MainActor
@Suite(.serialized)
struct StaleRegisteredBystanderDisplayIDTests {

    private struct StaleRegisteredFetcher: ModelFetching {
        let tasks: [TransitTask]
        let milestones: [Milestone]

        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            if T.self == TransitTask.self {
                return tasks.compactMap { $0 as? T }
            }
            if T.self == Milestone.self {
                return milestones.compactMap { $0 as? T }
            }
            return []
        }
    }

    private struct Environment {
        let container: ModelContainer
        let context: ModelContext
        let project: Project
        let taskAllocator: DisplayIDAllocator
        let milestoneAllocator: DisplayIDAllocator
        let taskService: TaskService
        let milestoneService: MilestoneService
        let maintenanceService: DisplayIDMaintenanceService
    }

    private func makeEnvironment() throws -> Environment {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = Project(name: "Test", description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let taskAllocator = DisplayIDAllocator(
            store: InMemoryCounterStore(initialNextDisplayID: 10)
        )
        let milestoneAllocator = DisplayIDAllocator(
            store: InMemoryCounterStore(initialNextDisplayID: 10)
        )
        let taskService = TaskService(
            modelContext: context,
            displayIDAllocator: taskAllocator
        )
        let milestoneService = MilestoneService(
            modelContext: context,
            displayIDAllocator: milestoneAllocator
        )
        let maintenanceService = DisplayIDMaintenanceService(
            modelContext: context,
            taskAllocator: taskAllocator,
            milestoneAllocator: milestoneAllocator,
            commentService: CommentService(modelContext: context)
        )

        return Environment(
            container: testContainer.container,
            context: context,
            project: project,
            taskAllocator: taskAllocator,
            milestoneAllocator: milestoneAllocator,
            taskService: taskService,
            milestoneService: milestoneService,
            maintenanceService: maintenanceService
        )
    }

    private func staleFetcher(in environment: Environment) -> StaleRegisteredFetcher {
        let task = TransitTask(
            name: "Cached task",
            type: .feature,
            project: environment.project,
            displayID: .permanent(9)
        )
        let milestone = Milestone(
            name: "Cached milestone",
            project: environment.project,
            displayID: .permanent(9)
        )
        return StaleRegisteredFetcher(tasks: [task], milestones: [milestone])
    }

    @discardableResult
    private func insertTask(
        in environment: Environment,
        name: String,
        displayID: DisplayID,
        creationDate: Date = .now
    ) -> TransitTask {
        let task = TransitTask(
            name: name,
            type: .feature,
            project: environment.project,
            displayID: displayID
        )
        task.creationDate = creationDate
        environment.context.insert(task)
        return task
    }

    @discardableResult
    private func insertMilestone(
        in environment: Environment,
        name: String,
        displayID: DisplayID,
        creationDate: Date = .now
    ) -> Milestone {
        let milestone = Milestone(
            name: name,
            project: environment.project,
            displayID: displayID
        )
        milestone.creationDate = creationDate
        environment.context.insert(milestone)
        return milestone
    }

    private func makeRegisteredTaskStale(
        _ task: TransitTask,
        in context: ModelContext
    ) throws {
        task.permanentDisplayId = 10
        try context.save()
        // The store now holds the peer-equivalent value 10. Restore only the
        // registered value to 9, without a fetch that could refresh it.
        task.permanentDisplayId = 9
    }

    private func makeRegisteredMilestoneStale(
        _ milestone: Milestone,
        in context: ModelContext
    ) throws {
        milestone.permanentDisplayId = 10
        try context.save()
        // Mirror T-1061's deterministic stale-cache fixture for milestones.
        milestone.permanentDisplayId = 9
    }

    private func storedTaskIDs(in container: ModelContainer) throws -> [Int] {
        let probe = ModelContext(container)
        return try probe.fetch(FetchDescriptor<TransitTask>()).compactMap(\.permanentDisplayId)
    }

    private func storedMilestoneIDs(in container: ModelContainer) throws -> [Int] {
        let probe = ModelContext(container)
        return try probe.fetch(FetchDescriptor<Milestone>()).compactMap(\.permanentDisplayId)
    }

    private func expectStaleRegisteredTask(
        _ task: TransitTask,
        in context: ModelContext
    ) {
        #expect(task.permanentDisplayId == 9,
                "The main-context bystander must remain stale for this regression")
        #expect(context.hasChanges,
                "The fixture must preserve the unsaved registered value")
    }

    private func expectStaleRegisteredMilestone(
        _ milestone: Milestone,
        in context: ModelContext
    ) {
        #expect(milestone.permanentDisplayId == 9,
                "The main-context bystander must remain stale for this regression")
        #expect(context.hasChanges,
                "The fixture must preserve the unsaved registered value")
    }

    @Test func taskCreationBlocksPeerCommittedIDHiddenByStaleRegisteredBystander() async throws {
        let environment = try makeEnvironment()
        let bystander = insertTask(
            in: environment,
            name: "Bystander",
            displayID: .permanent(9)
        )
        try environment.context.save()
        try makeRegisteredTaskStale(bystander, in: environment.context)
        expectStaleRegisteredTask(bystander, in: environment.context)

        let taskService = TaskService(
            modelContext: environment.context,
            displayIDAllocator: environment.taskAllocator,
            fetcher: staleFetcher(in: environment)
        )
        let created = try await taskService.createTask(
            name: "Created",
            description: nil,
            type: .feature,
            project: environment.project
        )

        #expect(created.permanentDisplayId == 11)
        let ids = try storedTaskIDs(in: environment.container)
        #expect(Set(ids).count == ids.count, "Creation must not duplicate the peer-committed ID")
    }

    @Test func milestoneCreationBlocksPeerCommittedIDHiddenByStaleRegisteredBystander() async throws {
        let environment = try makeEnvironment()
        let bystander = insertMilestone(
            in: environment,
            name: "Bystander",
            displayID: .permanent(9)
        )
        try environment.context.save()
        try makeRegisteredMilestoneStale(bystander, in: environment.context)
        expectStaleRegisteredMilestone(bystander, in: environment.context)

        let milestoneService = MilestoneService(
            modelContext: environment.context,
            displayIDAllocator: environment.milestoneAllocator,
            fetcher: staleFetcher(in: environment)
        )
        let created = try await milestoneService.createMilestone(
            name: "Created",
            description: nil,
            project: environment.project
        )

        #expect(created.permanentDisplayId == 11)
        let ids = try storedMilestoneIDs(in: environment.container)
        #expect(Set(ids).count == ids.count, "Creation must not duplicate the peer-committed ID")
    }

    @Test func taskPromotionBlocksPeerCommittedIDHiddenByStaleRegisteredBystander() async throws {
        let environment = try makeEnvironment()
        let bystander = insertTask(
            in: environment,
            name: "Bystander",
            displayID: .permanent(9)
        )
        let provisional = insertTask(
            in: environment,
            name: "Provisional",
            displayID: .provisional
        )
        try environment.context.save()
        try makeRegisteredTaskStale(bystander, in: environment.context)
        expectStaleRegisteredTask(bystander, in: environment.context)

        await environment.taskAllocator.promoteProvisionalTasks(
            in: environment.context,
            usedTaskIDs: { [9] }
        )

        #expect(provisional.permanentDisplayId == 11)
        let ids = try storedTaskIDs(in: environment.container)
        #expect(Set(ids).count == ids.count, "Promotion must not duplicate the peer-committed ID")
    }

    @Test func milestonePromotionBlocksPeerCommittedIDHiddenByStaleRegisteredBystander() async throws {
        let environment = try makeEnvironment()
        let bystander = insertMilestone(
            in: environment,
            name: "Bystander",
            displayID: .permanent(9)
        )
        let provisional = insertMilestone(
            in: environment,
            name: "Provisional",
            displayID: .provisional
        )
        try environment.context.save()
        try makeRegisteredMilestoneStale(bystander, in: environment.context)
        expectStaleRegisteredMilestone(bystander, in: environment.context)

        let milestoneService = MilestoneService(
            modelContext: environment.context,
            displayIDAllocator: environment.milestoneAllocator,
            fetcher: staleFetcher(in: environment)
        )
        await milestoneService.promoteProvisionalMilestones()

        #expect(provisional.permanentDisplayId == 11)
        let ids = try storedMilestoneIDs(in: environment.container)
        #expect(Set(ids).count == ids.count, "Promotion must not duplicate the peer-committed ID")
    }

    @Test func taskRepairBlocksPeerCommittedIDHiddenByStaleRegisteredBystander() async throws {
        let environment = try makeEnvironment()
        insertTask(
            in: environment,
            name: "Winner",
            displayID: .permanent(5),
            creationDate: Date(timeIntervalSince1970: 1_000)
        )
        insertTask(
            in: environment,
            name: "Loser",
            displayID: .permanent(5),
            creationDate: Date(timeIntervalSince1970: 2_000)
        )
        let bystander = insertTask(
            in: environment,
            name: "Bystander",
            displayID: .permanent(9),
            creationDate: Date(timeIntervalSince1970: 3_000)
        )
        try environment.context.save()
        try makeRegisteredTaskStale(bystander, in: environment.context)
        expectStaleRegisteredTask(bystander, in: environment.context)

        let maintenanceService = DisplayIDMaintenanceService(
            modelContext: environment.context,
            taskAllocator: DisplayIDAllocator(
                store: StaleReadCounterStore(staleValue: 10, staleReads: 3)
            ),
            milestoneAllocator: environment.milestoneAllocator,
            commentService: CommentService(modelContext: environment.context),
            usedIDFetcher: staleFetcher(in: environment)
        )
        let result = await maintenanceService.reassignDuplicates()

        let group = try #require(result.groups.first(where: { $0.type == .task }))
        #expect(group.failure == nil)
        #expect(group.reassignments.first?.newDisplayId == 11)
        let ids = try storedTaskIDs(in: environment.container)
        #expect(Set(ids).count == ids.count, "Repair must not duplicate the peer-committed ID")
    }

    @Test func milestoneRepairBlocksPeerCommittedIDHiddenByStaleRegisteredBystander() async throws {
        let environment = try makeEnvironment()
        insertMilestone(
            in: environment,
            name: "Winner",
            displayID: .permanent(5),
            creationDate: Date(timeIntervalSince1970: 1_000)
        )
        insertMilestone(
            in: environment,
            name: "Loser",
            displayID: .permanent(5),
            creationDate: Date(timeIntervalSince1970: 2_000)
        )
        let bystander = insertMilestone(
            in: environment,
            name: "Bystander",
            displayID: .permanent(9),
            creationDate: Date(timeIntervalSince1970: 3_000)
        )
        try environment.context.save()
        try makeRegisteredMilestoneStale(bystander, in: environment.context)
        expectStaleRegisteredMilestone(bystander, in: environment.context)

        let maintenanceService = DisplayIDMaintenanceService(
            modelContext: environment.context,
            taskAllocator: environment.taskAllocator,
            milestoneAllocator: DisplayIDAllocator(
                store: StaleReadCounterStore(staleValue: 10, staleReads: 3)
            ),
            commentService: CommentService(modelContext: environment.context),
            usedIDFetcher: staleFetcher(in: environment)
        )
        let result = await maintenanceService.reassignDuplicates()

        let group = try #require(result.groups.first(where: { $0.type == .milestone }))
        #expect(group.failure == nil)
        #expect(group.reassignments.first?.newDisplayId == 11)
        let ids = try storedMilestoneIDs(in: environment.container)
        #expect(Set(ids).count == ids.count, "Repair must not duplicate the peer-committed ID")
    }
}

// swiftlint:enable type_body_length
