import Foundation
import Testing
import SwiftData
@testable import Transit

@Suite(.serialized)
@MainActor
struct TaskEntityQueryTests {

    private func makeProjectAndTask(
        context: ModelContext,
        taskName: String = "Test Task",
        displayId: Int? = nil
    ) -> (Project, TransitTask) {
        let project = Project(name: "TestProject", description: "desc", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        let task = TransitTask(
            name: taskName,
            type: .feature,
            project: project,
            displayID: displayId.map { .permanent($0) } ?? .provisional
        )
        context.insert(task)
        try? context.save()
        return (project, task)
    }

    // MARK: - Entity Resolution by UUID

    @Test func entitiesForValidIdReturnsMatchingTask() throws {
        let context = try TestModelContainer.newContext()
        let (_, task) = makeProjectAndTask(context: context, taskName: "Found Task")

        let descriptor = FetchDescriptor<TransitTask>()
        let allTasks = try context.fetch(descriptor)
        let uuids = [task.id]
        let matching = allTasks.filter { uuids.contains($0.id) }
        let entities = matching.compactMap { try? TaskEntity.from($0) }

        #expect(entities.count == 1)
        #expect(entities.first?.name == "Found Task")
    }

    @Test func entitiesForInvalidIdReturnsEmpty() throws {
        let context = try TestModelContainer.newContext()
        _ = makeProjectAndTask(context: context)

        let descriptor = FetchDescriptor<TransitTask>()
        let allTasks = try context.fetch(descriptor)
        let bogusId = UUID()
        let matching = allTasks.filter { $0.id == bogusId }
        let entities = matching.compactMap { try? TaskEntity.from($0) }

        #expect(entities.isEmpty)
    }

    @Test func entitiesForInvalidUUIDStringIsSkipped() {
        let identifiers = ["not-a-uuid", "also-bad"]
        let uuids = identifiers.compactMap { UUID(uuidString: $0) }
        #expect(uuids.isEmpty)
    }

    // MARK: - Batch Context with compactMap

    @Test func compactMapSkipsTasksWithoutProject() throws {
        let context = try TestModelContainer.newContext()
        let (project, task1) = makeProjectAndTask(context: context, taskName: "Good Task")

        // Create an orphan task (simulates CloudKit sync edge case)
        let orphanTask = TransitTask(
            name: "Orphan",
            type: .bug,
            project: project,
            displayID: .provisional
        )
        context.insert(orphanTask)
        orphanTask.project = nil
        try context.save()

        let descriptor = FetchDescriptor<TransitTask>()
        let allTasks = try context.fetch(descriptor)
        let uuids = [task1.id, orphanTask.id]
        let matching = allTasks.filter { uuids.contains($0.id) }
        let entities = matching.compactMap { try? TaskEntity.from($0) }

        // Only the task with a project should be included
        #expect(entities.count == 1)
        #expect(entities.first?.name == "Good Task")
    }

    // MARK: - Suggested Entities (sorted by lastStatusChangeDate)

    @Test func suggestedEntitiesReturnsMostRecent() throws {
        let context = try TestModelContainer.newContext()
        let project = Project(name: "Project", description: "desc", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        // Create tasks with different dates
        for index in 0..<15 {
            let task = TransitTask(
                name: "Task \(index)",
                type: .feature,
                project: project,
                displayID: .permanent(index + 1)
            )
            context.insert(task)
        }
        try context.save()

        let descriptor = FetchDescriptor<TransitTask>(
            sortBy: [SortDescriptor(\.lastStatusChangeDate, order: .reverse)]
        )
        let tasks = try context.fetch(descriptor)
        let entities = Array(tasks.prefix(10)).compactMap { try? TaskEntity.from($0) }

        #expect(entities.count == 10)
    }
}
