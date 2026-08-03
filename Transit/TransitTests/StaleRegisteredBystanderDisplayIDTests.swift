import Foundation
import SwiftData
import Testing
@testable import Transit

// swiftlint:disable type_body_length

/// Regression coverage for T-1939. An independent peer context commits display
/// ID 10 while the receiving context keeps a clean registered value of 9. This
/// models the stale peer-merge snapshot directly and separately proves that
/// unsaved live IDs remain blocked by the combined collision set.
@MainActor
@Suite(.serialized)
struct StaleRegisteredBystanderDisplayIDTests {

    /// Deterministic live-context snapshot used after an independent peer commit.
    /// The models are the receiving context's actual registered objects, not
    /// detached substitutes, so the fixture proves they are clean and stale
    /// before this seam prevents a test fetch from refreshing them.
    private struct RegisteredSnapshotFetcher: ModelFetching {
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
        return Environment(
            container: testContainer.container,
            context: context,
            project: project,
            taskAllocator: taskAllocator,
            milestoneAllocator: milestoneAllocator
        )
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

    private func commitPeerTaskUpdateKeepingRegisteredBystanderStale(
        _ task: TransitTask,
        in environment: Environment
    ) throws {
        let taskID = task.id
        let peerContext = ModelContext(environment.container)
        let peerTask = try #require(try peerContext.fetch(FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == taskID }
        )).first)
        peerTask.permanentDisplayId = 10
        try peerContext.save()

        #expect(task.permanentDisplayId == 9,
                "The registered bystander must remain stale after the peer commit")
        #expect(!environment.context.hasChanges,
                "The stale bystander must be clean, not an unsaved local edit")
        #expect(try storedTaskIDs(in: environment.container).contains(10),
                "A transient context must observe the peer-committed ID")
    }

    private func commitPeerMilestoneUpdateKeepingRegisteredBystanderStale(
        _ milestone: Milestone,
        in environment: Environment
    ) throws {
        let milestoneID = milestone.id
        let peerContext = ModelContext(environment.container)
        let peerMilestone = try #require(try peerContext.fetch(FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == milestoneID }
        )).first)
        peerMilestone.permanentDisplayId = 10
        try peerContext.save()

        #expect(milestone.permanentDisplayId == 9,
                "The registered bystander must remain stale after the peer commit")
        #expect(!environment.context.hasChanges,
                "The stale bystander must be clean, not an unsaved local edit")
        #expect(try storedMilestoneIDs(in: environment.container).contains(10),
                "A transient context must observe the peer-committed ID")
    }

    private func storedTaskIDs(in container: ModelContainer) throws -> [Int] {
        let probe = ModelContext(container)
        return try probe.fetch(FetchDescriptor<TransitTask>()).compactMap(\.permanentDisplayId)
    }

    private func storedMilestoneIDs(in container: ModelContainer) throws -> [Int] {
        let probe = ModelContext(container)
        return try probe.fetch(FetchDescriptor<Milestone>()).compactMap(\.permanentDisplayId)
    }

    @Test func taskGuardUnionsPeerCommittedAndLivePendingIDs() throws {
        let environment = try makeEnvironment()
        let bystander = insertTask(
            in: environment,
            name: "Bystander",
            displayID: .permanent(9)
        )
        try environment.context.save()
        try commitPeerTaskUpdateKeepingRegisteredBystanderStale(bystander, in: environment)

        let pending = insertTask(in: environment, name: "Pending", displayID: .permanent(11))
        let live = RegisteredSnapshotFetcher(tasks: [bystander, pending], milestones: [])
        let ids = try UsedDisplayIDs(
            modelContext: environment.context,
            liveFetcher: live
        ).tasks()

        #expect(ids == [9, 10, 11],
                "The guard must union stale live, peer-committed, and unsaved IDs")
        #expect(bystander.permanentDisplayId == 9,
                "Building the guard must not refresh the registered bystander")
        #expect(environment.context.hasChanges,
                "The pending ID must remain unsaved after the read")
    }

    @Test func milestoneGuardUnionsPeerCommittedAndLivePendingIDs() throws {
        let environment = try makeEnvironment()
        let bystander = insertMilestone(
            in: environment,
            name: "Bystander",
            displayID: .permanent(9)
        )
        try environment.context.save()
        try commitPeerMilestoneUpdateKeepingRegisteredBystanderStale(bystander, in: environment)

        let pending = insertMilestone(in: environment, name: "Pending", displayID: .permanent(11))
        let live = RegisteredSnapshotFetcher(tasks: [], milestones: [bystander, pending])
        let ids = try UsedDisplayIDs(
            modelContext: environment.context,
            liveFetcher: live
        ).milestones()

        #expect(ids == [9, 10, 11],
                "The guard must union stale live, peer-committed, and unsaved IDs")
        #expect(bystander.permanentDisplayId == 9,
                "Building the guard must not refresh the registered bystander")
        #expect(environment.context.hasChanges,
                "The pending ID must remain unsaved after the read")
    }

    @Test func taskCreationBlocksPeerCommittedIDHiddenByStaleRegisteredBystander() async throws {
        let environment = try makeEnvironment()
        let bystander = insertTask(
            in: environment,
            name: "Bystander",
            displayID: .permanent(9)
        )
        try environment.context.save()
        try commitPeerTaskUpdateKeepingRegisteredBystanderStale(bystander, in: environment)

        let taskService = TaskService(
            modelContext: environment.context,
            displayIDAllocator: environment.taskAllocator,
            fetcher: RegisteredSnapshotFetcher(tasks: [bystander], milestones: [])
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
        try commitPeerMilestoneUpdateKeepingRegisteredBystanderStale(bystander, in: environment)

        let milestoneService = MilestoneService(
            modelContext: environment.context,
            displayIDAllocator: environment.milestoneAllocator,
            fetcher: RegisteredSnapshotFetcher(tasks: [], milestones: [bystander])
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
        try commitPeerTaskUpdateKeepingRegisteredBystanderStale(bystander, in: environment)

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
        try commitPeerMilestoneUpdateKeepingRegisteredBystanderStale(bystander, in: environment)

        let milestoneService = MilestoneService(
            modelContext: environment.context,
            displayIDAllocator: environment.milestoneAllocator,
            fetcher: RegisteredSnapshotFetcher(tasks: [], milestones: [bystander])
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
        try commitPeerTaskUpdateKeepingRegisteredBystanderStale(bystander, in: environment)

        let maintenanceService = DisplayIDMaintenanceService(
            modelContext: environment.context,
            taskAllocator: DisplayIDAllocator(
                store: StaleReadCounterStore(staleValue: 10, staleReads: 3)
            ),
            milestoneAllocator: environment.milestoneAllocator,
            commentService: CommentService(modelContext: environment.context),
            usedIDFetcher: RegisteredSnapshotFetcher(tasks: [bystander], milestones: [])
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
        try commitPeerMilestoneUpdateKeepingRegisteredBystanderStale(bystander, in: environment)

        let maintenanceService = DisplayIDMaintenanceService(
            modelContext: environment.context,
            taskAllocator: environment.taskAllocator,
            milestoneAllocator: DisplayIDAllocator(
                store: StaleReadCounterStore(staleValue: 10, staleReads: 3)
            ),
            commentService: CommentService(modelContext: environment.context),
            usedIDFetcher: RegisteredSnapshotFetcher(tasks: [], milestones: [bystander])
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
