import Foundation
import SwiftData
import Testing
@testable import Transit

/// Counter store that mimics an eventually-consistent CloudKit read: the first
/// `staleReads` calls to `loadCounter` serve `staleValue` regardless of what has
/// been written; later reads reflect committed writes. `staleReads: .max` models
/// a permanently stuck counter whose writes are never observed.
///
/// The change tag is always current, so compare-and-swap writes succeed — the
/// only thing that is wrong is the *value* the reader sees.
actor StaleReadCounterStore: DisplayIDAllocator.CounterStore {
    private var nextDisplayID: Int
    private var changeTag: Int = 0
    private let staleValue: Int
    private var staleReadsRemaining: Int

    init(staleValue: Int, staleReads: Int) {
        self.nextDisplayID = staleValue
        self.staleValue = staleValue
        self.staleReadsRemaining = staleReads
    }

    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        let value: Int
        if staleReadsRemaining > 0 {
            staleReadsRemaining -= 1
            value = staleValue
        } else {
            value = nextDisplayID
        }
        return DisplayIDAllocator.CounterSnapshot(nextDisplayID: value, changeTag: "\(changeTag)")
    }

    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
        guard expectedChangeTag == "\(changeTag)" else {
            throw DisplayIDAllocator.Error.conflict
        }
        self.nextDisplayID = nextDisplayID
        changeTag += 1
    }
}

/// Regression tests for T-1766: duplicate cleanup allocated replacement display
/// IDs without passing the committed used-ID set, so a stale or stuck counter
/// read could hand a loser an ID that another record already holds — turning one
/// collision into another, or leaving the original collision in place.
@MainActor
@Suite(.serialized)
struct DisplayIDMaintenanceStaleCounterTests {

    // MARK: - Helpers

    private struct TestEnv {
        let context: ModelContext
        let service: DisplayIDMaintenanceService
        let project: Project
    }

    private func makeEnv(
        taskStore: any DisplayIDAllocator.CounterStore,
        milestoneStore: any DisplayIDAllocator.CounterStore
    ) throws -> TestEnv {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let service = DisplayIDMaintenanceService(
            modelContext: context,
            taskAllocator: DisplayIDAllocator(store: taskStore),
            milestoneAllocator: DisplayIDAllocator(store: milestoneStore),
            commentService: CommentService(modelContext: context)
        )
        let project = Project(name: "Test", description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return TestEnv(context: context, service: service, project: project)
    }

    @discardableResult
    private func makeTask(
        in env: TestEnv, name: String, displayId: Int, creationDate: Date, id: UUID = UUID()
    ) -> TransitTask {
        let task = TransitTask(
            name: name, type: .feature, project: env.project, displayID: .permanent(displayId)
        )
        task.id = id
        task.creationDate = creationDate
        env.context.insert(task)
        return task
    }

    @discardableResult
    private func makeMilestone(
        in env: TestEnv, name: String, displayId: Int, creationDate: Date, id: UUID = UUID()
    ) -> Milestone {
        let milestone = Milestone(
            name: name, project: env.project, displayID: .permanent(displayId)
        )
        milestone.id = id
        milestone.creationDate = creationDate
        env.context.insert(milestone)
        return milestone
    }

    private func taskDisplayIDs(in env: TestEnv) throws -> [Int] {
        try env.context.fetch(FetchDescriptor<TransitTask>()).compactMap(\.permanentDisplayId)
    }

    private func milestoneDisplayIDs(in env: TestEnv) throws -> [Int] {
        try env.context.fetch(FetchDescriptor<Milestone>()).compactMap(\.permanentDisplayId)
    }

    // MARK: - Stale counter read

    /// T-5 is duplicated and T-9 exists. The fence advances the counter to 10,
    /// but the allocation read still serves the pre-advance value 5. Without the
    /// used-ID guard the loser is handed 5 straight back and the duplicate
    /// survives the "repair".
    @Test func taskLoserNeverGetsAnInUseIdWhenCounterReadIsStale() async throws {
        let env = try makeEnv(
            taskStore: StaleReadCounterStore(staleValue: 5, staleReads: 3),
            milestoneStore: StaleReadCounterStore(staleValue: 1, staleReads: 0)
        )
        let loserId = UUID()
        makeTask(in: env, name: "Winner", displayId: 5,
                 creationDate: Date(timeIntervalSince1970: 1000))
        makeTask(in: env, name: "Loser", displayId: 5,
                 creationDate: Date(timeIntervalSince1970: 2000), id: loserId)
        makeTask(in: env, name: "Bystander", displayId: 9,
                 creationDate: Date(timeIntervalSince1970: 3000))
        try env.context.save()

        let result = await env.service.reassignDuplicates()

        let group = try #require(result.groups.first(where: { $0.type == .task }))
        #expect(group.failure == nil)
        let entry = try #require(group.reassignments.first)
        #expect(entry.id == loserId)
        #expect(entry.newDisplayId != 5, "Reassigned ID must not be the duplicate it is meant to resolve")
        #expect(entry.newDisplayId != 9, "Reassigned ID must not collide with an unrelated task")

        let ids = try taskDisplayIDs(in: env)
        #expect(ids.count == 3)
        #expect(Set(ids).count == 3, "Cleanup must leave every task with a distinct display ID")
    }

    /// Milestone companion to `taskLoserNeverGetsAnInUseIdWhenCounterReadIsStale`.
    @Test func milestoneLoserNeverGetsAnInUseIdWhenCounterReadIsStale() async throws {
        let env = try makeEnv(
            taskStore: StaleReadCounterStore(staleValue: 1, staleReads: 0),
            milestoneStore: StaleReadCounterStore(staleValue: 3, staleReads: 3)
        )
        let loserId = UUID()
        makeMilestone(in: env, name: "Winner", displayId: 3,
                      creationDate: Date(timeIntervalSince1970: 1000))
        makeMilestone(in: env, name: "Loser", displayId: 3,
                      creationDate: Date(timeIntervalSince1970: 2000), id: loserId)
        makeMilestone(in: env, name: "Bystander", displayId: 7,
                      creationDate: Date(timeIntervalSince1970: 3000))
        try env.context.save()

        let result = await env.service.reassignDuplicates()

        let group = try #require(result.groups.first(where: { $0.type == .milestone }))
        #expect(group.failure == nil)
        let entry = try #require(group.reassignments.first)
        #expect(entry.id == loserId)
        #expect(entry.newDisplayId != 3, "Reassigned ID must not be the duplicate it is meant to resolve")
        #expect(entry.newDisplayId != 7, "Reassigned ID must not collide with an unrelated milestone")

        let ids = try milestoneDisplayIDs(in: env)
        #expect(ids.count == 3)
        #expect(Set(ids).count == 3, "Cleanup must leave every milestone with a distinct display ID")
    }

    // MARK: - Permanently stuck counter

    /// A counter whose writes are never observed can only ever offer an in-use
    /// ID. The run must exhaust its retries and report `.allocationFailed`
    /// rather than write a colliding ID onto the loser.
    @Test func taskLoserIsNotReassignedWhenStuckCounterOnlyOffersUsedIds() async throws {
        let env = try makeEnv(
            taskStore: StaleReadCounterStore(staleValue: 5, staleReads: .max),
            milestoneStore: StaleReadCounterStore(staleValue: 1, staleReads: 0)
        )
        let loserId = UUID()
        makeTask(in: env, name: "Winner", displayId: 5,
                 creationDate: Date(timeIntervalSince1970: 1000))
        makeTask(in: env, name: "Loser", displayId: 5,
                 creationDate: Date(timeIntervalSince1970: 2000), id: loserId)
        makeTask(in: env, name: "Bystander", displayId: 9,
                 creationDate: Date(timeIntervalSince1970: 3000))
        try env.context.save()

        let result = await env.service.reassignDuplicates()

        let group = try #require(result.groups.first(where: { $0.type == .task }))
        #expect(group.failure?.code == .allocationFailed)
        #expect(group.reassignments.isEmpty, "No ID may be written when the only candidates are in use")

        let tasks = try env.context.fetch(FetchDescriptor<TransitTask>())
        let loser = try #require(tasks.first(where: { $0.id == loserId }))
        #expect(loser.permanentDisplayId == 5, "Loser keeps its ID rather than being moved onto another")
    }

    /// Milestone companion to `taskLoserIsNotReassignedWhenStuckCounterOnlyOffersUsedIds`.
    @Test func milestoneLoserIsNotReassignedWhenStuckCounterOnlyOffersUsedIds() async throws {
        let env = try makeEnv(
            taskStore: StaleReadCounterStore(staleValue: 1, staleReads: 0),
            milestoneStore: StaleReadCounterStore(staleValue: 3, staleReads: .max)
        )
        let loserId = UUID()
        makeMilestone(in: env, name: "Winner", displayId: 3,
                      creationDate: Date(timeIntervalSince1970: 1000))
        makeMilestone(in: env, name: "Loser", displayId: 3,
                      creationDate: Date(timeIntervalSince1970: 2000), id: loserId)
        makeMilestone(in: env, name: "Bystander", displayId: 7,
                      creationDate: Date(timeIntervalSince1970: 3000))
        try env.context.save()

        let result = await env.service.reassignDuplicates()

        let group = try #require(result.groups.first(where: { $0.type == .milestone }))
        #expect(group.failure?.code == .allocationFailed)
        #expect(group.reassignments.isEmpty, "No ID may be written when the only candidates are in use")

        let milestones = try env.context.fetch(FetchDescriptor<Milestone>())
        let loser = try #require(milestones.first(where: { $0.id == loserId }))
        #expect(loser.permanentDisplayId == 3, "Loser keeps its ID rather than being moved onto another")
    }
}
