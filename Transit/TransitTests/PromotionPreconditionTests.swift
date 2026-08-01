import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-2020 fail-closed coverage for records removed while display-ID allocation
/// is suspended. The allocated value is consumed once, but no stale model is
/// mutated or saved and later lifecycle passes do not leak more values.
@MainActor @Suite(.serialized)
struct PromotionPreconditionTests {

    @Test func deletedTaskIsSkippedAfterAllocation() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let store = AllocationGatedCounterStore(initialNextDisplayID: 100)
        let allocator = DisplayIDAllocator(store: store)
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        let task = TransitTask(
            name: "Deleted by peer", type: .feature, project: project, displayID: .provisional
        )
        context.insert(task)
        try context.save()

        let taskID = task.id
        let peerContext = ModelContext(testContainer.container)
        let peerTask = try #require(try peerContext.fetch(FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == taskID }
        )).first)
        var saveCount = 0
        let promotion = Task { @MainActor in
            await allocator.promoteProvisionalTasks(in: context, save: { context in
                saveCount += 1
                try context.save()
            })
        }
        #expect(await store.waitUntilAllocationStarts(), "Task allocation never parked")

        peerContext.delete(peerTask)
        try peerContext.save()
        await store.releaseAllocation()
        await promotion.value

        #expect(saveCount == 0, "A deleted task must not be mutated or saved")
        let probe = ModelContext(testContainer.container)
        #expect(try probe.fetch(FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == taskID }
        )).isEmpty)
        #expect(await store.currentNextDisplayID() == 101,
                "The in-flight allocation is consumed when the record disappears")

        await allocator.promoteProvisionalTasks(in: context)
        #expect(await store.currentNextDisplayID() == 101,
                "A deleted record must not consume another value on a later pass")
    }

    @Test func deletedMilestoneIsSkippedAfterAllocation() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let store = AllocationGatedCounterStore(initialNextDisplayID: 200)
        let allocator = DisplayIDAllocator(store: store)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        let milestone = Milestone(
            name: "Deleted by peer", project: project, displayID: .provisional
        )
        context.insert(milestone)
        try context.save()

        let milestoneID = milestone.id
        let peerContext = ModelContext(testContainer.container)
        let peerMilestone = try #require(try peerContext.fetch(FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == milestoneID }
        )).first)
        var saveCount = 0
        let promotion = Task { @MainActor in
            await service.promoteProvisionalMilestones(save: { context in
                saveCount += 1
                try context.save()
            })
        }
        #expect(await store.waitUntilAllocationStarts(), "Milestone allocation never parked")

        peerContext.delete(peerMilestone)
        try peerContext.save()
        await store.releaseAllocation()
        await promotion.value

        #expect(saveCount == 0, "A deleted milestone must not be mutated or saved")
        let probe = ModelContext(testContainer.container)
        #expect(try probe.fetch(FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == milestoneID }
        )).isEmpty)
        #expect(await store.currentNextDisplayID() == 201,
                "The in-flight milestone allocation is consumed when the record disappears")

        await service.promoteProvisionalMilestones()
        #expect(await store.currentNextDisplayID() == 201,
                "A deleted milestone must not consume another value on a later pass")
    }
}
