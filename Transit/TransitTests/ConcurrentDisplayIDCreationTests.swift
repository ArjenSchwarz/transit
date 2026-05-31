import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1395: "Concurrent task creation can duplicate display IDs".
///
/// The CloudKit-backed counter uses optimistic locking, but a stale counter read
/// (e.g. eventual-consistency lag, or two automation runs reading the same value)
/// could hand back a `nextDisplayID` that is already in use by a committed task.
/// Nothing guarded against that at commit time, so two creates could persist the
/// same `permanentDisplayId`. These tests prove the guard: a freshly allocated ID
/// must never collide with an already-committed task/milestone.
@MainActor @Suite(.serialized)
struct ConcurrentDisplayIDCreationTests {

    // MARK: - Test doubles

    /// A counter store that always reports the same `nextDisplayID` regardless of
    /// how many times `saveCounter` succeeds. This deterministically simulates the
    /// real-world hazard the ticket describes: a stale read that re-hands an ID
    /// that has already been committed by a concurrent writer.
    private actor StuckCounterStore: DisplayIDAllocator.CounterStore {
        private let stuckValue: Int
        private(set) var savedValues: [Int] = []

        init(stuckValue: Int) {
            self.stuckValue = stuckValue
        }

        func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
            // changeTag stays constant so the optimistic-lock CAS always succeeds,
            // mimicking a counter that never actually advances on the server we read.
            DisplayIDAllocator.CounterSnapshot(nextDisplayID: stuckValue, changeTag: "stuck")
        }

        func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
            savedValues.append(nextDisplayID)
        }
    }

    /// A well-behaved counter that honours compare-and-swap and advances on each
    /// successful save — like the real CloudKit counter. Seeded so its first
    /// handout collides with an already-committed ID, modelling a peer/concurrent
    /// writer that consumed an ID our counter read missed.
    private actor AdvancingCounterStore: DisplayIDAllocator.CounterStore {
        private var nextDisplayID: Int
        private var changeTag = 0

        init(initialNextDisplayID: Int) {
            self.nextDisplayID = initialNextDisplayID
        }

        func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
            DisplayIDAllocator.CounterSnapshot(nextDisplayID: nextDisplayID, changeTag: "\(changeTag)")
        }

        func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
            guard expectedChangeTag == "\(changeTag)" else {
                throw DisplayIDAllocator.Error.conflict
            }
            self.nextDisplayID = nextDisplayID
            changeTag += 1
        }
    }

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let milestone: MilestoneService
        let context: ModelContext
    }

    /// Builds services with **separate** task and milestone allocators, mirroring
    /// production (CLAUDE.md: tasks and milestones use distinct allocator instances
    /// backed by different counter records). `makeStore` is invoked once per
    /// allocator so the two never share `issuedID` state. Each test exercises only
    /// one entity type, so the allocators are independent in practice.
    private func makeServices(makeStore: () -> DisplayIDAllocator.CounterStore) throws -> Services {
        let context = try TestModelContainer.newContext()
        let taskAllocator = DisplayIDAllocator(store: makeStore())
        let milestoneAllocator = DisplayIDAllocator(store: makeStore())
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: taskAllocator),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String = "P") -> Project {
        let project = Project(name: name, description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    private func allTasks(in context: ModelContext) throws -> [TransitTask] {
        try context.fetch(FetchDescriptor<TransitTask>())
    }

    private func allMilestones(in context: ModelContext) throws -> [Milestone] {
        try context.fetch(FetchDescriptor<Milestone>())
    }

    // MARK: - Tasks

    /// Two sequential creates against a stuck counter must NOT commit two tasks
    /// with the same permanentDisplayId. The second create must detect the local
    /// collision and allocate a fresh, unused ID instead.
    @Test func twoCreatesAgainstStuckCounterDoNotDuplicateTaskDisplayID() async throws {
        let svc = try makeServices { StuckCounterStore(stuckValue: 1392) }
        let project = makeProject(in: svc.context)

        let first = try await svc.task.createTask(
            name: "First", description: nil, type: .feature, project: project
        )
        let second = try await svc.task.createTask(
            name: "Second", description: nil, type: .feature, project: project
        )

        let ids = try allTasks(in: svc.context).compactMap(\.permanentDisplayId)
        #expect(Set(ids).count == ids.count, "Committed tasks must have unique display IDs")
        #expect(first.permanentDisplayId != second.permanentDisplayId)
    }

    /// Two *concurrent* creates against a permanently-stuck counter must never
    /// commit duplicate permanent IDs. Unlike the sequential case, the second
    /// caller's committed-ID snapshot is taken before the first caller has saved,
    /// so the guard relies on the allocator's in-process issued-ID tracking
    /// rather than on the committed set alone (T-1395). Against a counter that
    /// never advances, the second caller can exhaust its retries and fall back to
    /// a provisional ID — that is the designed offline behaviour. The invariant
    /// under test is *no duplicate permanent IDs*, not that both get one.
    @Test func concurrentCreatesAgainstStuckCounterDoNotDuplicateTaskDisplayID() async throws {
        let svc = try makeServices { StuckCounterStore(stuckValue: 1392) }
        let project = makeProject(in: svc.context)

        // Launch both creates as overlapping MainActor tasks. They cannot run
        // truly in parallel (both are @MainActor) but they interleave at the
        // allocator's `await`, which is exactly the hazard window the gate plus
        // issued-ID tracking must cover.
        // Return Void from each task — TransitTask is not Sendable and must not
        // cross back to the awaiting context (project memory note).
        let first = Task { @MainActor in
            _ = try await svc.task.createTask(
                name: "First", description: nil, type: .feature, project: project
            )
        }
        let second = Task { @MainActor in
            _ = try await svc.task.createTask(
                name: "Second", description: nil, type: .feature, project: project
            )
        }
        try await first.value
        try await second.value

        let ids = try allTasks(in: svc.context).compactMap(\.permanentDisplayId)
        #expect(Set(ids).count == ids.count, "Concurrent committed tasks must never share a permanent display ID")
    }

    /// When the (well-behaved, advancing) counter starts pointed at an ID that
    /// is already committed locally, the allocator must skip past the collision
    /// and hand out fresh, distinct IDs — never re-issuing the taken one.
    @Test func createSkipsCounterValueAlreadyCommittedLocally() async throws {
        // Counter would hand out 5 next, but 5 is already taken by an existing task.
        let svc = try makeServices { AdvancingCounterStore(initialNextDisplayID: 5) }
        let project = makeProject(in: svc.context)

        let existing = TransitTask(
            name: "Existing", type: .feature, project: project, displayID: .permanent(5)
        )
        svc.context.insert(existing)
        try svc.context.save()

        for index in 0..<5 {
            try await svc.task.createTask(
                name: "Task \(index)", description: nil, type: .feature, project: project
            )
        }

        let ids = try allTasks(in: svc.context).compactMap(\.permanentDisplayId)
        #expect(ids.count == 6, "Existing task plus five new tasks all have permanent IDs")
        #expect(Set(ids).count == 6, "All committed task IDs must be distinct")
        #expect(ids.filter { $0 == 5 }.count == 1, "The pre-committed ID 5 is never re-issued")
    }

    // MARK: - Milestones

    /// The same guard must protect milestone creation, which shares the allocator
    /// pattern (separate counter record).
    @Test func twoCreatesAgainstStuckCounterDoNotDuplicateMilestoneDisplayID() async throws {
        let svc = try makeServices { StuckCounterStore(stuckValue: 7) }
        let project = makeProject(in: svc.context)

        let first = try await svc.milestone.createMilestone(
            name: "M one", description: nil, project: project
        )
        let second = try await svc.milestone.createMilestone(
            name: "M two", description: nil, project: project
        )

        let ids = try allMilestones(in: svc.context).compactMap(\.permanentDisplayId)
        #expect(Set(ids).count == ids.count, "Committed milestones must have unique display IDs")
        #expect(first.permanentDisplayId != second.permanentDisplayId)
    }

    // MARK: - Concurrent allocation (contract documentation)

    /// Concurrent allocations against the real CAS store must each return a
    /// distinct ID. Documents the in-process serialization contract.
    @Test func concurrentAllocationsReturnDistinctIDs() async throws {
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store)

        // Fire many allocations concurrently; collect the results.
        let ids = await withTaskGroup(of: Int?.self) { group in
            for _ in 0..<20 {
                group.addTask { try? await allocator.allocateNextID() }
            }
            var collected: [Int] = []
            for await id in group {
                if let id { collected.append(id) }
            }
            return collected
        }

        #expect(ids.count == 20)
        #expect(Set(ids).count == ids.count, "Concurrent allocations must not collide")
    }
}
