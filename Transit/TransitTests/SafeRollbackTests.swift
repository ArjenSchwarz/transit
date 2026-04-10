import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-452: ModelContext.safeRollback() must re-fault
/// @Model properties after rollback so in-memory values match the reverted
/// persistent store.
///
/// These tests exercise the production `safeRollback()` extension directly,
/// verifying that each entity type's properties are properly re-faulted.
@MainActor @Suite(.serialized)
struct SafeRollbackTests {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        try TestModelContainer.newContext()
    }

    private func makeProject(
        name: String = "Test Project",
        in context: ModelContext
    ) -> Project {
        let project = Project(
            name: name,
            description: "A test project",
            gitRepo: "https://github.com/example/repo",
            colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }

    private func makeTask(
        name: String = "Test Task",
        project: Project,
        in context: ModelContext
    ) -> TransitTask {
        let task = TransitTask(
            name: name,
            type: TaskType.feature,
            project: project,
            displayID: .permanent(1)
        )
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        return task
    }

    // MARK: - Project re-faulting

    @Test func safeRollbackRevertsProjectProperties() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        try context.save()

        project.name = "Mutated"
        project.projectDescription = "Mutated desc"
        project.gitRepo = nil
        project.colorHex = "#00FF00"

        #expect(project.name == "Mutated")

        context.safeRollback()

        #expect(project.name == "Test Project")
        #expect(project.projectDescription == "A test project")
        #expect(project.gitRepo == "https://github.com/example/repo")
        #expect(project.colorHex == "#FF0000")
    }

    // MARK: - Task re-faulting

    @Test func safeRollbackRevertsTaskProperties() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let task = makeTask(project: project, in: context)
        try context.save()

        task.name = "Mutated Task"
        task.taskDescription = "Added description"
        task.type = TaskType.bug

        #expect(task.name == "Mutated Task")

        context.safeRollback()

        #expect(task.name == "Test Task")
        #expect(task.taskDescription == nil)
        #expect(task.type == TaskType.feature)
    }

    @Test func safeRollbackRevertsTaskStatusChange() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let task = makeTask(project: project, in: context)
        try context.save()

        #expect(task.status == TaskStatus.idea)

        StatusEngine.applyTransition(task: task, to: TaskStatus.planning)
        #expect(task.status == TaskStatus.planning)

        context.safeRollback()
        #expect(task.status == TaskStatus.idea)
    }

    // MARK: - Milestone re-faulting

    @Test func safeRollbackRevertsMilestoneProperties() throws {
        let context = try makeContext()
        let project = makeProject(in: context)

        let milestone = Milestone(
            name: "Original Milestone",
            description: "Original desc",
            project: project,
            displayID: .permanent(1)
        )
        context.insert(milestone)
        try context.save()

        milestone.name = "Mutated Milestone"
        milestone.milestoneDescription = "Mutated desc"
        milestone.statusRawValue = MilestoneStatus.done.rawValue

        #expect(milestone.name == "Mutated Milestone")

        context.safeRollback()

        #expect(milestone.name == "Original Milestone")
        #expect(milestone.milestoneDescription == "Original desc")
        #expect(milestone.statusRawValue == MilestoneStatus.open.rawValue)
    }

    // MARK: - Comment re-faulting

    @Test func safeRollbackRevertsCommentDeletion() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let task = makeTask(project: project, in: context)

        let comment = Transit.Comment(
            content: "Test comment",
            authorName: "Author",
            isAgent: false,
            task: task
        )
        context.insert(comment)
        try context.save()

        let commentID = comment.id
        context.delete(comment)

        context.safeRollback()

        let descriptor = FetchDescriptor<Transit.Comment>(
            predicate: #Predicate<Transit.Comment> { $0.id == commentID }
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.content == "Test comment")
    }

    // MARK: - Multi-entity atomicity

    @Test func safeRollbackRevertsMultipleEntityMutationsAtomically() throws {
        let context = try makeContext()
        let project = makeProject(name: "Original Project", in: context)
        let task = makeTask(name: "Original Task", project: project, in: context)

        let milestone = Milestone(
            name: "Original Milestone",
            description: nil,
            project: project,
            displayID: .permanent(1)
        )
        context.insert(milestone)
        try context.save()

        // Mutate multiple entities (simulating TaskEditView.save() pattern)
        project.name = "Mutated Project"
        task.name = "Mutated Task"
        task.milestone = milestone
        StatusEngine.applyTransition(task: task, to: TaskStatus.planning)
        milestone.name = "Mutated Milestone"

        context.safeRollback()

        #expect(project.name == "Original Project")
        #expect(task.name == "Original Task")
        #expect(task.status == TaskStatus.idea)
        #expect(task.milestone == nil)
        #expect(milestone.name == "Original Milestone")
    }

    // MARK: - Metadata re-faulting

    @Test func safeRollbackRevertsTaskMetadata() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        let task = TransitTask(
            name: "Task",
            type: TaskType.feature,
            project: project,
            displayID: .permanent(1),
            metadata: ["git.branch": "main"]
        )
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        try context.save()

        task.metadata = ["git.branch": "feature/new", "agent.id": "test"]
        #expect(task.metadata["agent.id"] == "test")

        context.safeRollback()

        #expect(task.metadata["git.branch"] == "main")
        #expect(task.metadata["agent.id"] == nil)
    }

    // MARK: - SyncHeartbeat re-faulting (T-777)

    @Test func safeRollbackRevertsSyncHeartbeatProperties() throws {
        let context = try makeContext()

        let heartbeat = SyncHeartbeat()
        context.insert(heartbeat)
        try context.save()

        let originalBeat = heartbeat.lastBeat

        // Mutate in memory — simulates a stale write that needs rollback
        heartbeat.lastBeat = Date.distantFuture

        #expect(heartbeat.lastBeat == Date.distantFuture)

        context.safeRollback()

        // After rollback + re-fault, lastBeat must match the saved value
        #expect(heartbeat.lastBeat == originalBeat)
    }
}
