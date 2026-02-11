import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

@Suite(.serialized)
@MainActor
struct TaskEntityQueryTests {

    // MARK: - Setup

    private func setupDependencies(context: ModelContext) -> ProjectService {
        let projectService = ProjectService(modelContext: context)
        AppDependencyManager.shared.add(dependency: projectService)
        return projectService
    }

    // MARK: - entities(for:)

    @Test func entitiesForIdentifiersReturnsMatchingTasks() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = Project(name: "Test Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let task1 = TransitTask(name: "Task 1", description: nil, type: .feature, project: project, displayID: .permanent(1), metadata: nil)
        let task2 = TransitTask(name: "Task 2", description: nil, type: .bug, project: project, displayID: .permanent(2), metadata: nil)
        let task3 = TransitTask(name: "Task 3", description: nil, type: .chore, project: project, displayID: .permanent(3), metadata: nil)
        context.insert(task1)
        context.insert(task2)
        context.insert(task3)

        let query = TaskEntityQuery()
        let identifiers = [task1.id.uuidString, task3.id.uuidString]
        let entities = try await query.entities(for: identifiers)

        #expect(entities.count == 2)
        #expect(entities.contains { $0.taskId == task1.id })
        #expect(entities.contains { $0.taskId == task3.id })
        #expect(!entities.contains { $0.taskId == task2.id })
    }

    @Test func entitiesForIdentifiersReturnsEmptyArrayWhenNoMatches() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = Project(name: "Test Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let task = TransitTask(name: "Task", description: nil, type: .feature, project: project, displayID: .permanent(1), metadata: nil)
        context.insert(task)

        let query = TaskEntityQuery()

        let nonExistentId = UUID().uuidString
        let entities = try await query.entities(for: [nonExistentId])

        #expect(entities.isEmpty)
    }

    @Test func entitiesForIdentifiersHandlesInvalidUUIDs() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = Project(name: "Test Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let task = TransitTask(name: "Task", description: nil, type: .feature, project: project, displayID: .permanent(1), metadata: nil)
        context.insert(task)

        let query = TaskEntityQuery()

        let invalidIdentifiers = ["not-a-uuid", "also-invalid", task.id.uuidString]
        let entities = try await query.entities(for: invalidIdentifiers)

        // Should only return the valid task
        #expect(entities.count == 1)
        #expect(entities[0].taskId == task.id)
    }

    @Test func entitiesForIdentifiersSkipsTasksWithoutProjects() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = Project(name: "Test Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let task1 = TransitTask(name: "Task 1", description: nil, type: .feature, project: project, displayID: .permanent(1), metadata: nil)
        let task2 = TransitTask(name: "Task 2", description: nil, type: .bug, project: project, displayID: .permanent(2), metadata: nil)
        context.insert(task1)
        context.insert(task2)

        // Simulate data integrity issue
        task2.project = nil

        let query = TaskEntityQuery()

        let identifiers = [task1.id.uuidString, task2.id.uuidString]
        let entities = try await query.entities(for: identifiers)

        // Should only return task1, gracefully skipping task2
        #expect(entities.count == 1)
        #expect(entities[0].taskId == task1.id)
    }

    @Test func entitiesForIdentifiersHandlesEmptyArray() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let query = TaskEntityQuery()

        let entities = try await query.entities(for: [])

        #expect(entities.isEmpty)
    }

    // MARK: - suggestedEntities()

    @Test func suggestedEntitiesReturnsRecentTasks() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = Project(name: "Test Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        // Create tasks with different lastStatusChangeDate values
        let task1 = TransitTask(name: "Oldest", description: nil, type: .feature, project: project, displayID: .permanent(1), metadata: nil)
        task1.lastStatusChangeDate = Date().addingTimeInterval(-3600) // 1 hour ago

        let task2 = TransitTask(name: "Newest", description: nil, type: .bug, project: project, displayID: .permanent(2), metadata: nil)
        task2.lastStatusChangeDate = Date() // Now

        let task3 = TransitTask(name: "Middle", description: nil, type: .chore, project: project, displayID: .permanent(3), metadata: nil)
        task3.lastStatusChangeDate = Date().addingTimeInterval(-1800) // 30 minutes ago

        context.insert(task1)
        context.insert(task2)
        context.insert(task3)

        let query = TaskEntityQuery()

        let entities = try await query.suggestedEntities()

        #expect(entities.count == 3)
        // Should be sorted by lastStatusChangeDate descending
        #expect(entities[0].name == "Newest")
        #expect(entities[1].name == "Middle")
        #expect(entities[2].name == "Oldest")
    }

    @Test func suggestedEntitiesLimitsToTenTasks() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = Project(name: "Test Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        // Create 15 tasks
        for i in 1...15 {
            let task = TransitTask(
                name: "Task \(i)",
                description: nil,
                type: .feature,
                project: project,
                displayID: .permanent(i),
                metadata: nil
            )
            task.lastStatusChangeDate = Date().addingTimeInterval(TimeInterval(-i * 60))
            context.insert(task)
        }

        let query = TaskEntityQuery()

        let entities = try await query.suggestedEntities()

        #expect(entities.count == 10)
    }

    @Test func suggestedEntitiesReturnsEmptyArrayWhenNoTasks() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let query = TaskEntityQuery()

        let entities = try await query.suggestedEntities()

        #expect(entities.isEmpty)
    }

    @Test func suggestedEntitiesSkipsTasksWithoutProjects() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = Project(name: "Test Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let task1 = TransitTask(name: "Valid Task", description: nil, type: .feature, project: project, displayID: .permanent(1), metadata: nil)
        let task2 = TransitTask(name: "Orphan Task", description: nil, type: .bug, project: project, displayID: .permanent(2), metadata: nil)
        context.insert(task1)
        context.insert(task2)

        // Simulate data integrity issue
        task2.project = nil

        let query = TaskEntityQuery()

        let entities = try await query.suggestedEntities()

        // Should only return task1, gracefully skipping task2
        #expect(entities.count == 1)
        #expect(entities[0].name == "Valid Task")
    }

    @Test func suggestedEntitiesHandlesAllTaskTypes() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = Project(name: "Test Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let types: [TaskType] = [.bug, .feature, .chore, .research, .documentation]
        for (index, taskType) in types.enumerated() {
            let task = TransitTask(
                name: "Task \(taskType.rawValue)",
                description: nil,
                type: taskType,
                project: project,
                displayID: .permanent(index + 1),
                metadata: nil
            )
            context.insert(task)
        }

        let query = TaskEntityQuery()

        let entities = try await query.suggestedEntities()

        #expect(entities.count == 5)
        #expect(entities.allSatisfy { entity in
            types.map { $0.rawValue }.contains(entity.type)
        })
    }

    @Test func suggestedEntitiesHandlesAllTaskStatuses() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = Project(name: "Test Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let statuses: [TaskStatus] = [
            .idea, .planning, .spec, .readyForImplementation,
            .inProgress, .readyForReview, .done, .abandoned
        ]

        for (index, status) in statuses.enumerated() {
            let task = TransitTask(
                name: "Task \(status.rawValue)",
                description: nil,
                type: .feature,
                project: project,
                displayID: .permanent(index + 1),
                metadata: nil
            )
            task.status = status
            context.insert(task)
        }

        let query = TaskEntityQuery()

        let entities = try await query.suggestedEntities()

        #expect(entities.count == 8)
        #expect(entities.allSatisfy { entity in
            statuses.map { $0.rawValue }.contains(entity.status)
        })
    }
}
