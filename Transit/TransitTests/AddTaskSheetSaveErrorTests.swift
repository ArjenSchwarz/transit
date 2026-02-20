import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-153: AddTaskSheet must not dismiss before task creation
/// completes. The fix awaits `taskService.createTask` and only dismisses on success,
/// showing an error alert on failure.
///
/// Since AddTaskSheet is a SwiftUI view, these tests verify the service-layer contract
/// the fix depends on: that `createTask` errors propagate (are not silently swallowed)
/// and that the task is not persisted when creation fails.
@MainActor @Suite(.serialized)
struct AddTaskSheetSaveErrorTests {

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

    // MARK: - Error propagation from createTask

    @Test func createTaskWithInvalidProjectIDThrowsProjectNotFound() async throws {
        let (service, _) = try makeService()
        let bogusProjectID = UUID()

        // This error was silently discarded by the old code (`_ = try await` in a
        // detached Task). The fix uses do/catch so this error surfaces to the user.
        do {
            _ = try await service.createTask(
                name: "Test Task",
                description: nil,
                type: .feature,
                projectID: bogusProjectID
            )
            Issue.record("Expected TaskService.Error.projectNotFound")
        } catch let error as TaskService.Error {
            #expect(error == .projectNotFound)
        }
    }

    /// Verifies the service rejects empty names even though AddTaskSheet.save()
    /// guards this before calling createTask. Documents the service-level contract
    /// so callers that skip view-level validation still get a clear error.
    @Test func createTaskWithEmptyNameThrowsInvalidName() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        do {
            _ = try await service.createTask(
                name: "   ",
                description: nil,
                type: .feature,
                project: project
            )
            Issue.record("Expected TaskService.Error.invalidName")
        } catch let error as TaskService.Error {
            #expect(error == .invalidName)
        }
    }

    @Test func noTaskPersistedWhenCreationFailsDueToInvalidProject() async throws {
        let (service, context) = try makeService()
        let bogusProjectID = UUID()

        _ = try? await service.createTask(
            name: "Ghost Task",
            description: nil,
            type: .feature,
            projectID: bogusProjectID
        )

        // Verify no task was inserted into the context
        let descriptor = FetchDescriptor<TransitTask>()
        let tasks = try context.fetch(descriptor)
        #expect(tasks.isEmpty)
    }

    @Test func successfulCreationReturnsPersistableTask() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        let task = try await service.createTask(
            name: "Valid Task",
            description: "Description",
            type: .feature,
            projectID: project.id
        )

        // Verify the task is persisted and queryable
        #expect(task.name == "Valid Task")
        #expect(task.status == .idea)

        let descriptor = FetchDescriptor<TransitTask>()
        let tasks = try context.fetch(descriptor)
        #expect(tasks.count == 1)
        #expect(tasks.first?.name == "Valid Task")
    }
}
