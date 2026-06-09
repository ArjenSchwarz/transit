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
///
/// Regression tests for T-855: AddTaskSheet must not leave an orphaned task when
/// the milestone assignment that follows `createTask` fails. The fix mirrors the
/// established cleanup pattern from `CreateTaskIntent` / MCP `create_task`
/// (T-558): on `setMilestone` failure after `createTask` succeeded, delete the
/// newly-created task before surfacing the error.
@MainActor @Suite(.serialized)
struct AddTaskSheetSaveErrorTests {

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let milestone: MilestoneService
        let context: ModelContext
    }

    private func makeService() throws -> (TaskService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        return (service, context)
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let taskAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: taskAllocator),
            milestone: MilestoneService(modelContext: context, displayIDAllocator: milestoneAllocator),
            context: context
        )
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

    @discardableResult
    private func makeMilestone(
        in context: ModelContext,
        name: String,
        project: Project,
        displayId: Int
    ) -> Milestone {
        let milestone = Milestone(
            name: name,
            description: nil,
            project: project,
            displayID: .permanent(displayId)
        )
        context.insert(milestone)
        return milestone
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

    // MARK: - T-855: Milestone assignment failure must not leave an orphan

    /// Reproduces the orphan scenario in `AddTaskSheet.persist`: the user
    /// selects a milestone, the task is created and saved, then `setMilestone`
    /// rejects the assignment (here via a project-mismatch — an unlikely but
    /// possible state if the milestone picker shows stale data). Before the
    /// T-855 fix the catch path only surfaced an error to the UI and left the
    /// newly-created task in the database.
    @Test func persistRollsBackTaskWhenMilestoneFailsProjectMismatch() async throws {
        let svc = try makeServices()
        let projectA = makeProject(in: svc.context, name: "Project A")
        let projectB = makeProject(in: svc.context, name: "Project B")
        let milestoneInB = makeMilestone(in: svc.context, name: "v1.0", project: projectB, displayId: 1)

        // Simulate the user picking projectA but a milestone bound to projectB.
        let draft = AddTaskSheet.TaskDraft(
            name: "Orphan Candidate",
            description: nil,
            type: .bug,
            priority: .medium,
            projectID: projectA.id,
            milestone: milestoneInB
        )
        await #expect(throws: MilestoneService.Error.projectMismatch) {
            try await AddTaskSheet.persist(
                draft: draft,
                taskService: svc.task,
                milestoneService: svc.milestone
            )
        }

        let descriptor = FetchDescriptor<TransitTask>()
        let tasks = try svc.context.fetch(descriptor)
        #expect(tasks.isEmpty, "Task must not remain in the database when milestone assignment fails [T-855]")
    }

    /// Verifies the happy-path: when a valid milestone in the same project is
    /// supplied, `persist` saves the task and assigns the milestone in one go.
    @Test func persistSucceedsWithValidMilestone() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let draft = AddTaskSheet.TaskDraft(
            name: "Happy Task",
            description: nil,
            type: .feature,
            priority: .medium,
            projectID: project.id,
            milestone: milestone
        )
        try await AddTaskSheet.persist(
            draft: draft,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 1)
        #expect(tasks.first?.milestone?.id == milestone.id)
    }

    /// Verifies that when no milestone is selected the helper still saves the
    /// task without attempting an assignment. This guards against an overly
    /// aggressive cleanup that might delete tasks unconditionally on any error.
    @Test func persistSucceedsWithoutMilestone() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let draft = AddTaskSheet.TaskDraft(
            name: "No Milestone Task",
            description: nil,
            type: .feature,
            priority: .medium,
            projectID: project.id,
            milestone: nil
        )
        try await AddTaskSheet.persist(
            draft: draft,
            taskService: svc.task,
            milestoneService: svc.milestone
        )

        let tasks = try svc.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 1)
        #expect(tasks.first?.milestone == nil)
    }
}
