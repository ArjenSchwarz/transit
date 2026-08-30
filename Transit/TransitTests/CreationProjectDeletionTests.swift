import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-2103 regressions for project deletion while creation is suspended in
/// display-ID allocation. An independent context models a peer or CloudKit merge
/// deleting the project after validation but before the create resumes.
@MainActor @Suite(.serialized)
struct CreationProjectDeletionTests {

    private func makeProject(in context: ModelContext) throws -> Project {
        let project = Project(
            name: "Deleted During Creation",
            description: "",
            gitRepo: nil,
            colorHex: "#000000"
        )
        context.insert(project)
        try context.save()
        return project
    }

    private func deleteProject(
        id: UUID,
        from container: ModelContainer
    ) throws {
        let peerContext = ModelContext(container)
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        let peerProject = try #require(try peerContext.fetch(descriptor).first)
        peerContext.delete(peerProject)
        try peerContext.save()
    }

    private func expectNoProjectsOrTasks(in container: ModelContainer) throws {
        let probe = ModelContext(container)
        #expect(try probe.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(
            try probe.fetch(FetchDescriptor<TransitTask>()).isEmpty,
            "Task creation must not commit an orphan after its project is deleted"
        )
    }

    private func expectNoProjectsOrMilestones(in container: ModelContainer) throws {
        let probe = ModelContext(container)
        #expect(try probe.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(
            try probe.fetch(FetchDescriptor<Milestone>()).isEmpty,
            "Milestone creation must not commit a record after its project is deleted"
        )
    }

    @Test func taskCreationRejectsProjectDeletedDuringAllocation() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let store = AllocationGatedCounterStore(initialNextDisplayID: 100)
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = try makeProject(in: context)
        let projectID = project.id

        let creation = Task { @MainActor in
            _ = try await service.createTask(
                name: "Must Not Persist",
                description: nil,
                type: .bug,
                project: project
            )
        }

        let allocationStarted = await store.waitUntilAllocationStarts()
        #expect(allocationStarted, "Task creation never reached the allocation suspension")
        guard allocationStarted else {
            creation.cancel()
            await store.releaseAllocation()
            _ = try? await creation.value
            return
        }

        try deleteProject(id: projectID, from: testContainer.container)
        await store.releaseAllocation()

        await #expect(throws: TaskService.Error.projectNotFound) {
            try await creation.value
        }

        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
        try expectNoProjectsOrTasks(in: testContainer.container)
    }

    @Test func milestoneCreationRejectsProjectDeletedDuringAllocation() async throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let store = AllocationGatedCounterStore(initialNextDisplayID: 200)
        let allocator = DisplayIDAllocator(store: store)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let project = try makeProject(in: context)
        let projectID = project.id

        let creation = Task { @MainActor in
            _ = try await service.createMilestone(
                name: "Must Not Persist",
                description: nil,
                project: project
            )
        }

        let allocationStarted = await store.waitUntilAllocationStarts()
        #expect(allocationStarted, "Milestone creation never reached the allocation suspension")
        guard allocationStarted else {
            creation.cancel()
            await store.releaseAllocation()
            _ = try? await creation.value
            return
        }

        try deleteProject(id: projectID, from: testContainer.container)
        await store.releaseAllocation()

        await #expect(throws: MilestoneService.Error.projectNotFound) {
            try await creation.value
        }

        #expect(try context.fetch(FetchDescriptor<Milestone>()).isEmpty)
        try expectNoProjectsOrMilestones(in: testContainer.container)
    }
}
