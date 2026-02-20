import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-150: Restore and abandon actions must not silently
/// discard save errors.
///
/// These tests verify that:
/// 1. TaskService.abandon() and restore() propagate errors (throwing contract)
/// 2. Rollback reverts status changes made by abandon/restore
/// 3. ProjectEditView's save path for existing projects also handles errors
///    (rollback reverts direct model mutations)
@MainActor @Suite(.serialized)
struct ActionButtonSaveErrorTests {

    // MARK: - Helpers

    private func makeService() throws -> (TaskService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        return (service, context)
    }

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(
            name: "Test Project",
            description: "A test project",
            gitRepo: nil,
            colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }

    // MARK: - Abandon rollback

    @Test func rollbackRevertsAbandonStatusChange() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Active Task",
            description: nil,
            type: .feature,
            project: project
        )
        try context.save()

        #expect(task.status == .idea)
        #expect(task.completionDate == nil)

        // Simulate what happens when abandon succeeds in-memory but we need to rollback
        StatusEngine.applyTransition(task: task, to: .abandoned)
        #expect(task.status == .abandoned)
        #expect(task.completionDate != nil)

        // Rollback should revert to the last persisted state
        context.rollback()

        #expect(task.status == .idea)
        #expect(task.completionDate == nil)
    }

    // MARK: - Restore rollback

    @Test func rollbackRevertsRestoreStatusChange() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Abandoned Task",
            description: nil,
            type: .bug,
            project: project
        )
        try service.abandon(task: task)
        try context.save()

        #expect(task.status == .abandoned)
        #expect(task.completionDate != nil)

        // Simulate what happens when restore succeeds in-memory but we need to rollback
        StatusEngine.applyTransition(task: task, to: .idea)
        #expect(task.status == .idea)
        #expect(task.completionDate == nil)

        // Rollback should revert to abandoned state
        context.rollback()

        #expect(task.status == .abandoned)
        #expect(task.completionDate != nil)
    }

    // MARK: - Throwing contract (documents that abandon/restore use `try`, not `try?`)

    @Test func abandonIsDeclaredThrowingAndSucceedsNormally() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Task",
            description: nil,
            type: .feature,
            project: project
        )

        // Verify abandon is a throwing function that succeeds on the happy path.
        // The view must call this with `try` (not `try?`) so errors surface.
        try service.abandon(task: task)
        #expect(task.status == .abandoned)
    }

    @Test func restoreIsDeclaredThrowingAndSucceedsNormally() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let task = try await service.createTask(
            name: "Task",
            description: nil,
            type: .feature,
            project: project
        )
        try service.abandon(task: task)

        // Verify restore is a throwing function that succeeds on the happy path.
        try service.restore(task: task)
        #expect(task.status == .idea)
    }

    // MARK: - Project edit rollback

    @Test func rollbackRevertsDirectProjectPropertyMutations() async throws {
        let (_, context) = try makeService()
        let project = makeProject(in: context)
        try context.save()

        #expect(project.name == "Test Project")
        #expect(project.projectDescription == "A test project")
        #expect(project.colorHex == "#FF0000")

        // Simulate what ProjectEditView.save() does for existing projects:
        // mutate properties directly, then save
        project.name = "Renamed Project"
        project.projectDescription = "Updated description"
        project.colorHex = "#00FF00"
        project.gitRepo = "https://github.com/test/repo"

        #expect(project.name == "Renamed Project")

        // Rollback should revert to the last persisted state
        context.rollback()

        #expect(project.name == "Test Project")
        #expect(project.projectDescription == "A test project")
        #expect(project.colorHex == "#FF0000")
        #expect(project.gitRepo == nil)
    }
}
