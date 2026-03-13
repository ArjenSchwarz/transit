import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-361: TaskEditView.save() must be atomic — all mutations
/// (project, milestone, status, properties) persist in a single save or
/// roll back together. Tests the `save: false` deferred-save pattern.
@MainActor @Suite(.serialized)
struct TaskEditAtomicSaveTests {

    // MARK: - Helpers

    private func makeService() throws -> (TaskService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        return (service, context)
    }

    private func makeMilestoneService(context: ModelContext) -> MilestoneService {
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return MilestoneService(modelContext: context, displayIDAllocator: allocator)
    }

    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(
            name: name,
            description: "A test project",
            gitRepo: nil,
            colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }

    // MARK: - Deferred save (save: false)

    @Test func changeProjectWithSaveFalseDoesNotPersist() async throws {
        let (service, context) = try makeService()
        let projectA = makeProject(in: context, name: "Project A")
        let projectB = makeProject(in: context, name: "Project B")
        let task = try await service.createTask(
            name: "Task",
            description: nil,
            type: .feature,
            project: projectA
        )
        try context.save()

        try service.changeProject(task: task, to: projectB, save: false)
        #expect(task.project?.id == projectB.id)

        TestModelContainer.rollback(context)
        #expect(task.project?.id == projectA.id)
    }

    @Test func setMilestoneWithSaveFalseDoesNotPersist() async throws {
        let (service, context) = try makeService()
        let milestoneService = makeMilestoneService(context: context)
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Task",
            description: nil,
            type: .feature,
            project: project
        )
        let milestone = try await milestoneService.createMilestone(
            name: "M1",
            description: nil,
            project: project
        )
        try context.save()

        try milestoneService.setMilestone(milestone, on: task, save: false)
        #expect(task.milestone?.id == milestone.id)

        TestModelContainer.rollback(context)
        #expect(task.milestone == nil)
    }

    @Test func updateStatusWithSaveFalseDoesNotPersist() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Task",
            description: nil,
            type: .feature,
            project: project
        )
        try context.save()

        #expect(task.status == .idea)
        try service.updateStatus(task: task, to: .planning, save: false)
        #expect(task.status == .planning)

        TestModelContainer.rollback(context)
        #expect(task.status == .idea)
    }

    @Test func atomicSaveCommitsAllDeferredChanges() async throws {
        let (service, context) = try makeService()
        let milestoneService = makeMilestoneService(context: context)
        let projectA = makeProject(in: context, name: "Project A")
        let projectB = makeProject(in: context, name: "Project B")
        let milestoneB = try await milestoneService.createMilestone(
            name: "M-B",
            description: nil,
            project: projectB
        )
        let task = try await service.createTask(
            name: "Original",
            description: nil,
            type: .feature,
            project: projectA
        )
        try context.save()

        task.name = "Updated"
        task.type = .bug
        try service.changeProject(task: task, to: projectB, save: false)
        try milestoneService.setMilestone(milestoneB, on: task, save: false)
        try service.updateStatus(task: task, to: .planning, save: false)

        try context.save()

        #expect(task.name == "Updated")
        #expect(task.type == .bug)
        #expect(task.project?.id == projectB.id)
        #expect(task.milestone?.id == milestoneB.id)
        #expect(task.status == .planning)
    }

    @Test func rollbackAfterPartialDeferredMutationsRevertsAll() async throws {
        let (service, context) = try makeService()
        let milestoneService = makeMilestoneService(context: context)
        let projectA = makeProject(in: context, name: "Project A")
        let projectB = makeProject(in: context, name: "Project B")
        let milestoneB = try await milestoneService.createMilestone(
            name: "M-B",
            description: nil,
            project: projectB
        )
        let task = try await service.createTask(
            name: "Original",
            description: "Original desc",
            type: .feature,
            project: projectA
        )
        try context.save()

        task.name = "Updated"
        task.taskDescription = "Updated desc"
        task.type = .bug
        try service.changeProject(task: task, to: projectB, save: false)
        try milestoneService.setMilestone(milestoneB, on: task, save: false)
        try service.updateStatus(task: task, to: .planning, save: false)

        #expect(task.name == "Updated")
        #expect(task.project?.id == projectB.id)
        #expect(task.milestone?.id == milestoneB.id)
        #expect(task.status == .planning)

        TestModelContainer.rollback(context)

        #expect(task.name == "Original")
        #expect(task.taskDescription == "Original desc")
        #expect(task.type == .feature)
        #expect(task.project?.id == projectA.id)
        #expect(task.milestone == nil)
        #expect(task.status == .idea)
    }
}
