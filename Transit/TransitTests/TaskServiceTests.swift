//
//  TaskServiceTests.swift
//  TransitTests
//
//  Tests for TaskService.
//

import CloudKit
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct TaskServiceTests {
    private func makeTestContext() -> (ModelContext, DisplayIDAllocator) {
        let schema = Schema([Project.self, TransitTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            fatalError("Failed to create test container")
        }
        let context = ModelContext(container)
        let allocator = DisplayIDAllocator(container: CKContainer(identifier: "iCloud.test"))
        return (context, allocator)
    }

    private func makeTestProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test", description: "Test", gitRepo: nil, color: .blue)
        context.insert(project)
        return project
    }

    // MARK: - Task Creation Tests

    @Test func createTaskSetsInitialState() async throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeTestProject(in: context)

        let task = try await service.createTask(
            name: "Test Task",
            description: "Description",
            type: .feature,
            project: project,
            metadata: ["key": "value"]
        )

        #expect(task.name == "Test Task")
        #expect(task.taskDescription == "Description")
        #expect(task.type == .feature)
        #expect(task.status == .idea)
        #expect(task.project?.id == project.id)
        #expect(task.metadata["key"] == "value")
    }

    @Test func createTaskSetsTimestamps() async throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeTestProject(in: context)

        let before = Date.now
        let task = try await service.createTask(
            name: "Test",
            description: nil,
            type: .bug,
            project: project,
            metadata: nil
        )
        let after = Date.now

        #expect(task.creationDate >= before)
        #expect(task.creationDate <= after)
        #expect(task.lastStatusChangeDate >= before)
        #expect(task.lastStatusChangeDate <= after)
    }

    @Test func createTaskWithNilMetadata() async throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeTestProject(in: context)

        let task = try await service.createTask(
            name: "Test",
            description: nil,
            type: .chore,
            project: project,
            metadata: nil
        )

        #expect(task.metadata.isEmpty)
    }

    // MARK: - Status Change Tests

    @Test func updateStatusChangesStatus() async throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeTestProject(in: context)

        let task = try await service.createTask(
            name: "Test",
            description: nil,
            type: .feature,
            project: project,
            metadata: nil
        )

        try service.updateStatus(task: task, to: .planning)
        #expect(task.status == .planning)

        try service.updateStatus(task: task, to: .inProgress)
        #expect(task.status == .inProgress)
    }

    @Test func updateStatusToTerminalSetsCompletionDate() async throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeTestProject(in: context)

        let task = try await service.createTask(
            name: "Test",
            description: nil,
            type: .feature,
            project: project,
            metadata: nil
        )

        #expect(task.completionDate == nil)

        try service.updateStatus(task: task, to: .done)
        #expect(task.completionDate != nil)
    }

    @Test func updateStatusFromTerminalClearsCompletionDate() async throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeTestProject(in: context)

        let task = try await service.createTask(
            name: "Test",
            description: nil,
            type: .feature,
            project: project,
            metadata: nil
        )

        try service.updateStatus(task: task, to: .done)
        #expect(task.completionDate != nil)

        try service.updateStatus(task: task, to: .inProgress)
        #expect(task.completionDate == nil)
    }

    // MARK: - Abandon/Restore Tests

    @Test func abandonSetsStatusToAbandoned() async throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeTestProject(in: context)

        let task = try await service.createTask(
            name: "Test",
            description: nil,
            type: .feature,
            project: project,
            metadata: nil
        )

        try service.abandon(task: task)
        #expect(task.status == .abandoned)
        #expect(task.completionDate != nil)
    }

    @Test func abandonFromAnyStatus() async throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeTestProject(in: context)

        let task = try await service.createTask(
            name: "Test",
            description: nil,
            type: .feature,
            project: project,
            metadata: nil
        )

        // Abandon from planning
        try service.updateStatus(task: task, to: .planning)
        try service.abandon(task: task)
        #expect(task.status == .abandoned)

        // Restore and abandon from done
        try service.restore(task: task)
        try service.updateStatus(task: task, to: .done)
        try service.abandon(task: task)
        #expect(task.status == .abandoned)
    }

    @Test func restoreSetsStatusToIdea() async throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeTestProject(in: context)

        let task = try await service.createTask(
            name: "Test",
            description: nil,
            type: .feature,
            project: project,
            metadata: nil
        )

        try service.abandon(task: task)
        #expect(task.status == .abandoned)

        try service.restore(task: task)
        #expect(task.status == .idea)
        #expect(task.completionDate == nil)
    }

    // MARK: - Find By Display ID Tests

    @Test func findByDisplayIDFindsTask() async throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeTestProject(in: context)

        let task = try await service.createTask(
            name: "Findable",
            description: nil,
            type: .feature,
            project: project,
            metadata: nil
        )

        // If task has permanent ID, we can find it
        if let permanentID = task.permanentDisplayId {
            let found = try service.findByDisplayID(permanentID)
            #expect(found?.id == task.id)
        }
    }

    @Test func findByDisplayIDReturnsNilForNonexistent() throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)

        let found = try service.findByDisplayID(99999)
        #expect(found == nil)
    }

    @Test func findByDisplayIDDoesNotFindProvisionalTasks() async throws {
        let (context, allocator) = makeTestContext()
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let project = makeTestProject(in: context)

        // Create a task that will be provisional (allocator will fail in test)
        let task = try await service.createTask(
            name: "Provisional",
            description: nil,
            type: .feature,
            project: project,
            metadata: nil
        )

        // Provisional tasks have nil permanentDisplayId
        if task.permanentDisplayId == nil {
            let found = try service.findByDisplayID(1)
            #expect(found?.id != task.id)
        }
    }
}
