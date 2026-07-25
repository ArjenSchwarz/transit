import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1764: "Concurrent milestone creation bypasses name uniqueness".
///
/// `MilestoneService.createMilestone` checks `milestoneNameExists` *before* awaiting
/// display-ID allocation. That await is a suspension point, so two overlapping creates
/// could both pass the check, both resume, and both insert the same case-insensitive
/// name in one project. SwiftData + CloudKit cannot express `@Attribute(.unique)`, so
/// this service-level check is the only thing enforcing the invariant — there is no
/// database constraint underneath it.
///
/// Sequential creates already rejected duplicates, so the regression has to pin the
/// *interleaving*: the contender must run its uniqueness check in the window between
/// the holder passing its own check and the holder committing. The tests do that
/// deterministically (see `GatedCounterStore` and `EntryFlag` below) rather than
/// relying on timing.
@MainActor @Suite(.serialized)
struct ConcurrentMilestoneNameUniquenessTests {

    // MARK: - Test doubles

    /// A counter store whose **first** `loadCounter` call blocks until the test
    /// explicitly releases it. `allocateNextID` reads the counter while holding the
    /// allocation gate, so blocking the first read parks the holder mid-create — after
    /// its uniqueness check, before its insert — and makes any concurrent create queue
    /// behind it. That is exactly the check-to-use window this ticket is about.
    private actor GatedCounterStore: DisplayIDAllocator.CounterStore {
        private var nextDisplayID: Int
        private var changeTag = 0

        private var firstLoadStarted = false
        private var firstLoadReached: CheckedContinuation<Void, Never>?

        private var hasReleased = false
        private var releaseContinuation: CheckedContinuation<Void, Never>?

        init(initialNextDisplayID: Int = 1) {
            self.nextDisplayID = initialNextDisplayID
        }

        /// Suspends until the first `loadCounter` call has been entered, i.e. the
        /// holder now owns the allocation gate and is parked inside its create.
        func waitUntilGateHeld() async {
            if firstLoadStarted { return }
            await withCheckedContinuation { firstLoadReached = $0 }
        }

        /// Lets the blocked first `loadCounter` call proceed so the holder can finish
        /// and release the gate — preventing a leaked continuation on teardown.
        func releaseGate() {
            hasReleased = true
            releaseContinuation?.resume()
            releaseContinuation = nil
        }

        func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
            if !firstLoadStarted {
                firstLoadStarted = true
                firstLoadReached?.resume()
                firstLoadReached = nil

                if !hasReleased {
                    await withCheckedContinuation { releaseContinuation = $0 }
                }
            }
            return DisplayIDAllocator.CounterSnapshot(
                nextDisplayID: nextDisplayID,
                changeTag: "\(changeTag)"
            )
        }

        func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
            guard expectedChangeTag == "\(changeTag)" else {
                throw DisplayIDAllocator.Error.conflict
            }
            self.nextDisplayID = nextDisplayID
            changeTag += 1
        }
    }

    /// Records that the contender's task body started running. Everything from this
    /// flag being set through `createMilestone`'s uniqueness check runs in a single
    /// MainActor job with no suspension in between, so a test that observes the flag
    /// set (from a *later* job) knows the contender has already made its check.
    private final class EntryFlag {
        var hasEntered = false
    }

    // MARK: - Helpers

    private func makeProject(in context: ModelContext, name: String = "P") -> Project {
        let project = Project(name: name, description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    /// Spins the MainActor until the contender's job has run. Bounded so a scheduling
    /// change can never hang the suite; callers assert the flag afterwards so the test
    /// fails loudly instead of passing vacuously if the interleaving never happened.
    private func waitUntilContenderEntered(_ flag: EntryFlag) async {
        var spins = 0
        while !flag.hasEntered && spins < 100 {
            await Task.yield()
            spins += 1
        }
    }

    private func milestones(named name: String, in context: ModelContext) throws -> [Milestone] {
        try context.fetch(FetchDescriptor<Milestone>()).filter {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    // MARK: - Tests

    /// Two overlapping creates of the same (case-insensitively equal) name in one
    /// project must not both persist. The contender's uniqueness check runs while the
    /// holder is parked in allocation, so the check is already stale by the time the
    /// contender resumes — it must re-check before inserting.
    @Test func interleavedCreatesWithSameNameRejectTheSecond() async throws {
        let context = try TestModelContainer.newContext()
        let store = GatedCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let project = makeProject(in: context)
        try context.save()

        // Holder: passes its uniqueness check, then parks inside display-ID allocation.
        let holder = Task { @MainActor in
            _ = try await service.createMilestone(name: "Beta", description: nil, project: project)
        }
        await store.waitUntilGateHeld()

        // Contender: makes its (soon to be stale) uniqueness check while the holder is
        // still parked and has inserted nothing, then queues on the allocation gate.
        let flag = EntryFlag()
        let contender = Task { @MainActor in
            flag.hasEntered = true
            _ = try await service.createMilestone(name: "beta", description: nil, project: project)
        }
        await waitUntilContenderEntered(flag)
        #expect(flag.hasEntered, "Contender must run its uniqueness check before the holder commits")

        await store.releaseGate()
        _ = try await holder.value

        await #expect(throws: MilestoneService.Error.duplicateName) {
            try await contender.value
        }

        let matches = try milestones(named: "beta", in: context)
        #expect(
            matches.count == 1,
            "Only one milestone named 'Beta' may exist in the project, found \(matches.count)"
        )
    }

    /// The re-check must not over-reject: two overlapping creates with *different*
    /// names in the same project both belong in the store.
    @Test func interleavedCreatesWithDifferentNamesBothSucceed() async throws {
        let context = try TestModelContainer.newContext()
        let store = GatedCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let project = makeProject(in: context)
        try context.save()

        let holder = Task { @MainActor in
            _ = try await service.createMilestone(name: "Alpha", description: nil, project: project)
        }
        await store.waitUntilGateHeld()

        let flag = EntryFlag()
        let contender = Task { @MainActor in
            flag.hasEntered = true
            _ = try await service.createMilestone(name: "Beta", description: nil, project: project)
        }
        await waitUntilContenderEntered(flag)
        #expect(flag.hasEntered)

        await store.releaseGate()
        _ = try await holder.value
        _ = try await contender.value

        let all = try context.fetch(FetchDescriptor<Milestone>())
        #expect(all.count == 2, "Both distinct names must persist, found \(all.count)")
        #expect(Set(all.compactMap(\.permanentDisplayId)).count == 2, "Display IDs must stay distinct")
    }

    /// Milestone names are unique *per project*, so the re-check must stay
    /// project-scoped: the same name in two different projects is legal even when the
    /// creates interleave.
    @Test func interleavedCreatesWithSameNameInDifferentProjectsBothSucceed() async throws {
        let context = try TestModelContainer.newContext()
        let store = GatedCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let projectOne = makeProject(in: context, name: "One")
        let projectTwo = makeProject(in: context, name: "Two")
        try context.save()

        let holder = Task { @MainActor in
            _ = try await service.createMilestone(name: "Beta", description: nil, project: projectOne)
        }
        await store.waitUntilGateHeld()

        let flag = EntryFlag()
        let contender = Task { @MainActor in
            flag.hasEntered = true
            _ = try await service.createMilestone(name: "Beta", description: nil, project: projectTwo)
        }
        await waitUntilContenderEntered(flag)
        #expect(flag.hasEntered)

        await store.releaseGate()
        _ = try await holder.value
        _ = try await contender.value

        let matches = try milestones(named: "Beta", in: context)
        #expect(matches.count == 2, "Same name in two projects is legal, found \(matches.count)")
    }
}
