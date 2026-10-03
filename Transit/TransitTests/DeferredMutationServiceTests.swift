import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct DeferredMutationServiceTests {
    @Test func taskPreparationPinsReferencesWithoutInserting() async throws {
        let fixture = try TestModelContainer()
        let context = fixture.context
        context.autosaveEnabled = false
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "red")
        context.insert(project)
        let milestone = Milestone(name: "M", project: project, displayID: .permanent(1))
        context.insert(milestone)
        try context.save()
        let counter = DeferredServiceCounter()
        let service = TaskService(modelContext: context, displayIDAllocator: DisplayIDAllocator(store: counter))
        let operation = Task {
            try await service.prepareTaskCreation(name: " T ", description: nil, type: .feature,
                                                   project: project, milestone: milestone)
        }
        await counter.waitForLoad()
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
        milestone.statusRawValue = MilestoneStatus.done.rawValue
        try context.save()
        await counter.release()
        let prepared = try await operation.value
        #expect(throws: TaskService.Error.milestoneNotOpen) { try service.applyTaskCreation(prepared) }
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }

    @Test func milestonePreparationRechecksCompetingNamesAfterSuspension() async throws {
        let fixture = try TestModelContainer()
        let context = fixture.context
        context.autosaveEnabled = false
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "red")
        context.insert(project)
        try context.save()
        let counter = DeferredServiceCounter()
        let service = MilestoneService(modelContext: context, displayIDAllocator: DisplayIDAllocator(store: counter))
        let operation = Task {
            try await service.prepareMilestoneCreation(name: "M", description: nil, project: project)
        }
        await counter.waitForLoad()
        let competitor = Milestone(name: "m", project: project, displayID: .permanent(50))
        context.insert(competitor)
        try context.save()
        await counter.release()
        let prepared = try await operation.value
        #expect(throws: MilestoneService.Error.duplicateName) { try service.applyMilestoneCreation(prepared) }
        #expect(try context.fetch(FetchDescriptor<Milestone>()).count == 1)
    }

    @Test func cancelledAllocationNeverInserts() async throws {
        let fixture = try TestModelContainer()
        let context = fixture.context
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "red")
        context.insert(project)
        try context.save()
        let counter = DeferredServiceCounter()
        let service = TaskService(modelContext: context, displayIDAllocator: DisplayIDAllocator(store: counter))
        let operation = Task {
            _ = try await service.createTask(name: "T", description: nil, type: .feature, project: project)
        }
        await counter.waitForLoad()
        operation.cancel()
        await counter.release()
        do {
            _ = try await operation.value
            Issue.record("Cancelled creation succeeded")
        } catch is CancellationError { }
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }

    @Test func projectAndMilestoneDeletionDeferPersistence() async throws {
        let fixture = try TestModelContainer()
        let context = fixture.context
        context.autosaveEnabled = false
        let project = try ProjectService(modelContext: context).createProject(
            name: "P", description: "", gitRepo: nil, colorHex: "red", save: false
        )
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<Project>()).isEmpty)
        try context.save()
        let milestones = MilestoneService(modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore()))
        let milestone = try await milestones.createMilestone(name: "M", description: nil, project: project)
        try milestones.deleteMilestone(milestone, save: false)
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<Milestone>()).count == 1)
        try context.save()
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<Milestone>()).isEmpty)
    }
}

private actor DeferredServiceCounter: DisplayIDAllocator.CounterStore {
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var started = false

    func waitForLoad() async {
        if started { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func release() { loadContinuation?.resume(); loadContinuation = nil }

    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        started = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { loadContinuation = $0 }
        return .init(nextDisplayID: 1, changeTag: nil)
    }

    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws { }
}
