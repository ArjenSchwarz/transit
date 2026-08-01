import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1614 and T-1621: service-layer helpers that derive an
/// invariant from a fetch result must not collapse a storage failure into a
/// permissive answer.
///
/// Both defects had the same shape — `(try? modelContext.fetch(...)) ?? []` — and
/// both are only interesting at the *caller*. Asserting that a helper throws proves
/// nothing; what matters is that the mutation the helper guards does not happen:
///
/// - T-1614: a failed duplicate check must not create a duplicate-named project or
///   milestone. CloudKit-backed SwiftData forbids `@Attribute(.unique)`, so the
///   check is the entire invariant.
/// - T-1621: a failed used-ID fetch must not let the allocator issue a display ID
///   that a local record already holds.
///
/// The seam is `ModelFetching`. `FailingFetcher` breaks only the invariant reads;
/// inserts and saves still go to the real context, which is exactly the situation
/// that made the old behaviour dangerous — the write succeeded, so nothing surfaced.
@MainActor @Suite(.serialized)
struct FetchFailureInvariantTests {

    // MARK: - Failing fetch seam

    private struct FetchFailure: Swift.Error {}

    /// A `ModelFetching` whose every fetch fails, simulating an unreadable store.
    private struct FailingFetcher: ModelFetching {
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            throw FetchFailure()
        }
    }

    // MARK: - T-1614: project name uniqueness

    @Test func projectCreateWithUnreadableStoreDoesNotCommitDuplicateName() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let working = ProjectService(modelContext: context)
        try working.createProject(name: "Transit", description: "", gitRepo: nil, colorHex: "#FF0000")

        let degraded = ProjectService(modelContext: context, fetcher: FailingFetcher())

        // Expected: the storage failure propagates. Before the fix the duplicate check
        // read `false` and a second "transit" was inserted and saved.
        #expect(throws: (any Swift.Error).self) {
            _ = try degraded.createProject(name: "transit", description: "", gitRepo: nil, colorHex: "#00FF00")
        }

        let projects = try context.fetch(FetchDescriptor<Project>())
        #expect(projects.count == 1, "A failed duplicate check must not create a second project")
    }

    @Test func projectRenameWithUnreadableStoreDoesNotCommitDuplicateName() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let working = ProjectService(modelContext: context)
        try working.createProject(name: "Transit", description: "", gitRepo: nil, colorHex: "#FF0000")
        let orbit = try working.createProject(name: "Orbit", description: "", gitRepo: nil, colorHex: "#00FF00")

        let degraded = ProjectService(modelContext: context, fetcher: FailingFetcher())

        #expect(throws: (any Swift.Error).self) {
            try degraded.updateProject(orbit, name: "Transit", description: "", gitRepo: nil, colorHex: "#00FF00")
        }

        let projects = try context.fetch(FetchDescriptor<Project>())
        let names = Set(projects.map { $0.name.lowercased() })
        #expect(names == ["transit", "orbit"], "A failed duplicate check must not rename onto a taken name")
    }

    // MARK: - T-1614: milestone name uniqueness

    @Test func milestoneCreateWithUnreadableStoreDoesNotCommitDuplicateName() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let project = try ProjectService(modelContext: context)
            .createProject(name: "Transit", description: "", gitRepo: nil, colorHex: "#FF0000")

        let working = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        try await working.createMilestone(name: "v1.0", description: nil, project: project)

        let degraded = MilestoneService(
            modelContext: context, displayIDAllocator: allocator, fetcher: FailingFetcher()
        )

        await #expect(throws: (any Swift.Error).self) {
            _ = try await degraded.createMilestone(name: "V1.0", description: nil, project: project)
        }

        let milestones = try context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.count == 1, "A failed duplicate check must not create a second milestone")
    }

    @Test func milestoneRenameWithUnreadableStoreDoesNotCommitDuplicateName() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let project = try ProjectService(modelContext: context)
            .createProject(name: "Transit", description: "", gitRepo: nil, colorHex: "#FF0000")

        let working = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        try await working.createMilestone(name: "v1.0", description: nil, project: project)
        let beta = try await working.createMilestone(name: "Beta", description: nil, project: project)

        let degraded = MilestoneService(
            modelContext: context, displayIDAllocator: allocator, fetcher: FailingFetcher()
        )

        #expect(throws: (any Swift.Error).self) {
            try degraded.updateMilestone(beta, name: "v1.0", description: nil)
        }

        let names = Set(try context.fetch(FetchDescriptor<Milestone>()).map { $0.name.lowercased() })
        #expect(names == ["v1.0", "beta"], "A failed duplicate check must not rename onto a taken name")
    }

    // MARK: - T-1621: used display IDs

    /// Seeds one task holding display ID 5 and returns a counter parked on 5, so the
    /// only thing standing between the allocator and a duplicate is the used-ID set.
    private func seedTaskHoldingID5(in context: ModelContext) throws -> Project {
        let project = try ProjectService(modelContext: context)
            .createProject(name: "Transit", description: "", gitRepo: nil, colorHex: "#FF0000")
        let existing = TransitTask(
            name: "Existing", description: nil, type: .bug, project: project, displayID: .permanent(5)
        )
        context.insert(existing)
        try context.save()
        return project
    }

    @Test func taskCreateWithUnreadableStoreDoesNotReissueCommittedDisplayID() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = try seedTaskHoldingID5(in: context)
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 5))

        let degraded = TaskService(
            modelContext: context, displayIDAllocator: allocator, fetcher: FailingFetcher()
        )

        // Expected: allocation fails because the collision guard could not be evaluated.
        // Before the fix the used-ID set read as empty, the stale candidate 5 was
        // accepted, and a second T-5 was saved.
        await #expect(throws: DisplayIDAllocator.Error.self) {
            _ = try await degraded.createTask(name: "New", description: nil, type: .bug, project: project)
        }

        let withID5 = try context.fetch(
            FetchDescriptor<TransitTask>(predicate: #Predicate { $0.permanentDisplayId == 5 })
        )
        #expect(withID5.count == 1, "A failed used-ID fetch must not reissue an in-use display ID")
    }

    @Test func taskCreateWithReadableStoreStillSkipsPastTheInUseID() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = try seedTaskHoldingID5(in: context)
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 5))

        // Control: with a working fetch the guard fires normally and allocation
        // advances past the occupied ID, so the fix did not turn a live path into a
        // failure path.
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let task = try await service.createTask(name: "New", description: nil, type: .bug, project: project)

        #expect(task.permanentDisplayId == 6)
    }

    @Test func milestonePromotionWithUnreadableStoreDoesNotReissueCommittedDisplayID() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = try ProjectService(modelContext: context)
            .createProject(name: "Transit", description: "", gitRepo: nil, colorHex: "#FF0000")
        let committed = Milestone(name: "v1.0", description: nil, project: project, displayID: .permanent(5))
        let provisional = Milestone(name: "Beta", description: nil, project: project, displayID: .provisional)
        context.insert(committed)
        context.insert(provisional)
        try context.save()

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 5))
        // Promotion never touches the name check, so an always-failing fetcher isolates
        // the used-ID read as the only thing that breaks.
        let degraded = MilestoneService(
            modelContext: context, displayIDAllocator: allocator, fetcher: FailingFetcher()
        )

        await degraded.promoteProvisionalMilestones()

        #expect(provisional.permanentDisplayId == nil, "Promotion must not assign an in-use display ID")
        let withID5 = try context.fetch(
            FetchDescriptor<Milestone>(predicate: #Predicate { $0.permanentDisplayId == 5 })
        )
        #expect(withID5.count == 1)
    }

    @Test func taskPromotionWithUnreadableStoreDoesNotReissueCommittedDisplayID() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = try seedTaskHoldingID5(in: context)
        let provisional = TransitTask(
            name: "Pending", description: nil, type: .bug, project: project, displayID: .provisional
        )
        context.insert(provisional)
        try context.save()

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 5))

        // The allocator's own committed-ID probe is the third copy of the defect
        // (T-1621); inject a failing read of it directly.
        await allocator.promoteProvisionalTasks(
            in: context,
            usedTaskIDs: { throw FetchFailure() }
        )

        #expect(provisional.permanentDisplayId == nil, "Promotion must not assign an in-use display ID")
        let withID5 = try context.fetch(
            FetchDescriptor<TransitTask>(predicate: #Predicate { $0.permanentDisplayId == 5 })
        )
        #expect(withID5.count == 1)
    }

    @Test func taskPromotionWithReadableStoreStillPromotesPastTheInUseID() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = try seedTaskHoldingID5(in: context)
        let provisional = TransitTask(
            name: "Pending", description: nil, type: .bug, project: project, displayID: .provisional
        )
        context.insert(provisional)
        try context.save()

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 5))
        await allocator.promoteProvisionalTasks(in: context)

        #expect(provisional.permanentDisplayId == 6)
    }
}
