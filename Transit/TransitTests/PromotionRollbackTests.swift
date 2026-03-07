import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-281: Rollback provisional ID promotion on save failure.
///
/// When promoteProvisionalTasks or promoteProvisionalMilestones sets
/// permanentDisplayId and the subsequent save() fails, the in-memory model
/// must be rolled back so it doesn't show a permanent ID that was never
/// persisted. These tests verify that rollback() correctly reverts
/// permanentDisplayId to nil, which is the mechanism the fix relies on.
@MainActor @Suite(.serialized)
struct PromotionRollbackTests {

    // MARK: - Task rollback mechanism

    /// Verifies that rollback() reverts an unsaved permanentDisplayId change
    /// on a task back to nil. This is the mechanism that the fix in
    /// promoteProvisionalTasks relies on.
    @Test func rollbackRevertsTaskPermanentDisplayIdToProvisional() throws {
        let context = try TestModelContainer.newContext()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .provisional)
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        try context.save()

        #expect(task.permanentDisplayId == nil)
        #expect(task.displayID == .provisional)

        // Simulate what promoteProvisionalTasks does: set permanentDisplayId
        // then save fails, requiring rollback
        task.permanentDisplayId = 42
        #expect(task.permanentDisplayId == 42)

        context.rollback()

        #expect(task.permanentDisplayId == nil)
        #expect(task.displayID == .provisional)
    }

    // MARK: - Milestone rollback mechanism

    /// Verifies that rollback() reverts an unsaved permanentDisplayId change
    /// on a milestone back to nil. This is the mechanism that the fix in
    /// promoteProvisionalMilestones relies on.
    @Test func rollbackRevertsMilestonePermanentDisplayIdToProvisional() throws {
        let context = try TestModelContainer.newContext()
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        let milestone = Milestone(name: "v1.0", description: nil, project: project, displayID: .provisional)
        context.insert(milestone)
        try context.save()

        #expect(milestone.permanentDisplayId == nil)
        #expect(milestone.displayID == .provisional)

        // Simulate promotion then save failure
        milestone.permanentDisplayId = 10
        #expect(milestone.permanentDisplayId == 10)

        context.rollback()

        #expect(milestone.permanentDisplayId == nil)
        #expect(milestone.displayID == .provisional)
    }

    // MARK: - Promotion integration
    //
    // Note: These integration tests exercise the "allocator fails before
    // permanentDisplayId is set" path, not the "save fails after
    // permanentDisplayId is set" path (which is the actual T-281 bug).
    // Injecting a ModelContext.save() failure is impractical with the
    // current TestModelContainer setup. The mechanism tests above (tests
    // 1 & 2) verify that rollback correctly reverts permanentDisplayId,
    // which is the mechanism the fix relies on.

    /// Verifies that promoteProvisionalTasks promotes the first task
    /// and leaves the second provisional when the allocator fails
    /// on the second allocation.
    @Test func promoteProvisionalTasksStopsOnAllocatorFailure() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 100)
        await store.enqueueSaveOutcomes([
            .success,
            .failure(DisplayIDAllocator.Error.retriesExhausted)
        ])
        let allocator = DisplayIDAllocator(store: store, retryLimit: 1)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)

        let task1 = TransitTask(name: "First", type: .feature, project: project, displayID: .provisional)
        task1.creationDate = Date(timeIntervalSince1970: 1000)
        StatusEngine.initializeNewTask(task1)
        context.insert(task1)

        let task2 = TransitTask(name: "Second", type: .feature, project: project, displayID: .provisional)
        task2.creationDate = Date(timeIntervalSince1970: 2000)
        StatusEngine.initializeNewTask(task2)
        context.insert(task2)
        try context.save()

        await allocator.promoteProvisionalTasks(in: context)

        // First task promoted successfully
        #expect(task1.permanentDisplayId == 100)

        // Second task stays provisional — allocator threw before
        // permanentDisplayId was set
        #expect(task2.permanentDisplayId == nil)
        #expect(task2.displayID == .provisional)
    }

    /// Verifies that promoteProvisionalMilestones promotes the first
    /// milestone and leaves the second provisional when the allocator
    /// fails on the second allocation.
    @Test func promoteProvisionalMilestonesStopsOnAllocatorFailure() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 50)
        await store.enqueueSaveOutcomes([
            .success,
            .failure(DisplayIDAllocator.Error.retriesExhausted)
        ])
        let allocator = DisplayIDAllocator(store: store, retryLimit: 1)
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)

        let milestone1 = Milestone(name: "v1.0", description: nil, project: project, displayID: .provisional)
        milestone1.creationDate = Date(timeIntervalSince1970: 1000)
        context.insert(milestone1)

        let milestone2 = Milestone(name: "v2.0", description: nil, project: project, displayID: .provisional)
        milestone2.creationDate = Date(timeIntervalSince1970: 2000)
        context.insert(milestone2)
        try context.save()

        await milestoneService.promoteProvisionalMilestones()

        // First milestone promoted
        #expect(milestone1.permanentDisplayId == 50)

        // Second milestone stays provisional
        #expect(milestone2.permanentDisplayId == nil)
        #expect(milestone2.displayID == .provisional)
    }
}
