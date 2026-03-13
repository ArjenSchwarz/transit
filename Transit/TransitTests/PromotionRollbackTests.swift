import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for ID promotion failure handling.
///
/// T-449 fixed a regression where connectivity-triggered ID promotion used
/// `ModelContext.rollback()` after a failed save. Because promotion runs on the
/// shared UI context, that rollback discarded unrelated unsaved edits that the
/// user was still making. These tests verify promotion now reverts only the
/// provisional ID change instead of clobbering the whole context.
@MainActor @Suite(.serialized)
struct PromotionRollbackTests {

    private enum SaveFailure: Swift.Error {
        case simulated
    }

    @Test func promoteProvisionalTasksFailedSavePreservesUnrelatedUnsavedEdits() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 100)
        let allocator = DisplayIDAllocator(store: store, retryLimit: 1)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)

        let promotedTask = TransitTask(name: "Promote Me", type: .feature, project: project, displayID: .provisional)
        StatusEngine.initializeNewTask(promotedTask)
        context.insert(promotedTask)

        let editedTask = TransitTask(name: "Draft Name", type: .feature, project: project, displayID: .permanent(7))
        StatusEngine.initializeNewTask(editedTask)
        context.insert(editedTask)
        try context.save()

        editedTask.name = "Edited While Offline"

        await allocator.promoteProvisionalTasks(in: context, save: { _ in
            throw SaveFailure.simulated
        })

        #expect(promotedTask.permanentDisplayId == nil)
        #expect(promotedTask.displayID == .provisional)
        #expect(editedTask.name == "Edited While Offline")
    }

    @Test func promoteProvisionalMilestonesFailedSavePreservesUnrelatedUnsavedEdits() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore(initialNextDisplayID: 50)
        let allocator = DisplayIDAllocator(store: store, retryLimit: 1)
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)

        let promotedMilestone = Milestone(name: "v1.0", description: nil, project: project, displayID: .provisional)
        context.insert(promotedMilestone)
        try context.save()

        project.projectDescription = "Edited while promotion retries"

        await milestoneService.promoteProvisionalMilestones(save: { _ in
            throw SaveFailure.simulated
        })

        #expect(promotedMilestone.permanentDisplayId == nil)
        #expect(promotedMilestone.displayID == .provisional)
        #expect(project.projectDescription == "Edited while promotion retries")
    }

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

        #expect(task1.permanentDisplayId == 100)
        #expect(task2.permanentDisplayId == nil)
        #expect(task2.displayID == .provisional)
    }

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

        #expect(milestone1.permanentDisplayId == 50)
        #expect(milestone2.permanentDisplayId == nil)
        #expect(milestone2.displayID == .provisional)
    }
}
