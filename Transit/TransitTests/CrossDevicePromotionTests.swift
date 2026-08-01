import Foundation
import SwiftData
import Testing
@testable import Transit

/// Controlled T-2020 store-merge regressions. Independent contexts model a peer
/// change that has already reached the receiving device's local SwiftData store.
@MainActor @Suite(.serialized)
struct CrossDevicePromotionTests {

    private func expectStoredTaskAndProject(
        in container: ModelContainer,
        taskID: UUID,
        projectID: UUID,
        expectedTaskDisplayID: Int
    ) throws {
        let probe = ModelContext(container)
        let storedTask = try #require(try probe.fetch(FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == taskID }
        )).first)
        #expect(storedTask.permanentDisplayId == expectedTaskDisplayID,
                "A peer's permanent task ID must survive promotion")
        try expectProjectDraftRemainsUnsaved(in: probe, projectID: projectID)
    }

    private func expectStoredMilestoneAndProject(
        in container: ModelContainer,
        milestoneID: UUID,
        projectID: UUID,
        expectedMilestoneDisplayID: Int
    ) throws {
        let probe = ModelContext(container)
        let storedMilestone = try #require(try probe.fetch(FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == milestoneID }
        )).first)
        #expect(storedMilestone.permanentDisplayId == expectedMilestoneDisplayID,
                "A peer's permanent milestone ID must survive promotion")
        try expectProjectDraftRemainsUnsaved(in: probe, projectID: projectID)
    }

    private func expectProjectDraftRemainsUnsaved(
        in probe: ModelContext,
        projectID: UUID
    ) throws {
        let storedProject = try #require(try probe.fetch(FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectID }
        )).first)
        #expect(storedProject.projectDescription == "",
                "Promotion must not persist an unrelated draft when the peer wins")
    }

    @Test func taskPeerPromotionDuringAllocationIsPreserved() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let gateStore = AllocationGatedCounterStore(initialNextDisplayID: 100)
        let allocator = DisplayIDAllocator(store: gateStore)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        let task = TransitTask(
            name: "Synced provisional", type: .feature, project: project, displayID: .provisional
        )
        context.insert(task)
        try context.save()

        let taskID = task.id
        let projectID = project.id
        let peerContext = ModelContext(testContainer.container)
        let peerTask = try #require(try peerContext.fetch(FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.id == taskID }
        )).first)
        project.projectDescription = "Unsaved task-promotion draft"

        var promotionSaveCount = 0
        let promotion = Task { @MainActor in
            await allocator.promoteProvisionalTasks(in: context, save: { context in
                promotionSaveCount += 1
                try context.save()
            })
        }
        #expect(await gateStore.waitUntilAllocationStarts(), "Task allocation never parked")

        peerTask.permanentDisplayId = 900
        try peerContext.save()
        await gateStore.releaseAllocation()
        await promotion.value

        #expect(promotionSaveCount == 0,
                "Task promotion must not save after a peer assigns a permanent ID")
        #expect(project.projectDescription == "Unsaved task-promotion draft")
        #expect(context.hasChanges, "Peer-win promotion must preserve unrelated dirty state")
        try expectStoredTaskAndProject(
            in: testContainer.container,
            taskID: taskID,
            projectID: projectID,
            expectedTaskDisplayID: 900
        )
        #expect(await gateStore.currentNextDisplayID() == 101,
                "The allocated counter value is deliberately consumed when the peer wins")

        await allocator.promoteProvisionalTasks(in: context, save: { context in
            promotionSaveCount += 1
            try context.save()
        })
        #expect(promotionSaveCount == 0)
        #expect(await gateStore.currentNextDisplayID() == 101,
                "A committed peer ID must not leak another counter value on a later pass")
    }

    @Test func milestonePeerPromotionDuringAllocationIsPreserved() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let gateStore = AllocationGatedCounterStore(initialNextDisplayID: 200)
        let allocator = DisplayIDAllocator(store: gateStore)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let project = Project(name: "P", description: "", gitRepo: nil, colorHex: "#000000")
        context.insert(project)
        let milestone = Milestone(
            name: "Synced provisional", description: nil, project: project, displayID: .provisional
        )
        context.insert(milestone)
        try context.save()

        let milestoneID = milestone.id
        let projectID = project.id
        let peerContext = ModelContext(testContainer.container)
        let peerMilestone = try #require(try peerContext.fetch(FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == milestoneID }
        )).first)
        project.projectDescription = "Unsaved milestone-promotion draft"

        var promotionSaveCount = 0
        let promotion = Task { @MainActor in
            await service.promoteProvisionalMilestones(save: { context in
                promotionSaveCount += 1
                try context.save()
            })
        }
        #expect(await gateStore.waitUntilAllocationStarts(), "Milestone allocation never parked")

        peerMilestone.permanentDisplayId = 901
        try peerContext.save()
        await gateStore.releaseAllocation()
        await promotion.value

        #expect(promotionSaveCount == 0,
                "Milestone promotion must not save after a peer assigns a permanent ID")
        #expect(project.projectDescription == "Unsaved milestone-promotion draft")
        #expect(context.hasChanges, "Peer-win promotion must preserve unrelated dirty state")
        try expectStoredMilestoneAndProject(
            in: testContainer.container,
            milestoneID: milestoneID,
            projectID: projectID,
            expectedMilestoneDisplayID: 901
        )
        #expect(await gateStore.currentNextDisplayID() == 201,
                "The allocated counter value is deliberately consumed when the peer wins")

        await service.promoteProvisionalMilestones(save: { context in
            promotionSaveCount += 1
            try context.save()
        })
        #expect(promotionSaveCount == 0)
        #expect(await gateStore.currentNextDisplayID() == 201,
                "A committed peer milestone ID must not leak another value on a later pass")
    }
}
