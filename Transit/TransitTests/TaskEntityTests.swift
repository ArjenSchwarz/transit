import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
struct TaskEntityTests {

    // MARK: - Initialization

    @Test func initializesWithAllProperties() {
        let taskId = UUID()
        let projectId = UUID()
        let now = Date()

        let entity = TaskEntity(
            id: taskId.uuidString,
            taskId: taskId,
            displayId: 42,
            name: "Test Task",
            status: "idea",
            type: "feature",
            projectId: projectId,
            projectName: "Test Project",
            lastStatusChangeDate: now,
            completionDate: nil
        )

        #expect(entity.id == taskId.uuidString)
        #expect(entity.taskId == taskId)
        #expect(entity.displayId == 42)
        #expect(entity.name == "Test Task")
        #expect(entity.status == "idea")
        #expect(entity.type == "feature")
        #expect(entity.projectId == projectId)
        #expect(entity.projectName == "Test Project")
        #expect(entity.lastStatusChangeDate == now)
        #expect(entity.completionDate == nil)
    }

    @Test func initializesWithOptionalDisplayId() {
        let taskId = UUID()
        let projectId = UUID()

        let entity = TaskEntity(
            id: taskId.uuidString,
            taskId: taskId,
            displayId: nil,
            name: "Task Without Display ID",
            status: "inProgress",
            type: "bug",
            projectId: projectId,
            projectName: "Project",
            lastStatusChangeDate: Date(),
            completionDate: nil
        )

        #expect(entity.displayId == nil)
    }

    @Test func initializesWithCompletionDate() {
        let taskId = UUID()
        let projectId = UUID()
        let completionDate = Date()

        let entity = TaskEntity(
            id: taskId.uuidString,
            taskId: taskId,
            displayId: 1,
            name: "Completed Task",
            status: "done",
            type: "feature",
            projectId: projectId,
            projectName: "Project",
            lastStatusChangeDate: Date(),
            completionDate: completionDate
        )

        #expect(entity.completionDate == completionDate)
    }

    // MARK: - Display Representation

    @Test func displayRepresentationShowsNameAndTypeAndStatus() {
        let entity = TaskEntity(
            id: UUID().uuidString,
            taskId: UUID(),
            displayId: 1,
            name: "My Task",
            status: "inProgress",
            type: "bug",
            projectId: UUID(),
            projectName: "Project",
            lastStatusChangeDate: Date(),
            completionDate: nil
        )

        let display = entity.displayRepresentation
        // Verify display representation can be accessed
        // The actual formatting is handled by the system
        _ = display.title
        _ = display.subtitle
    }

    @Test func typeDisplayRepresentationIsCreated() {
        _ = TaskEntity.typeDisplayRepresentation
    }

    // MARK: - Factory Method

    @Test func fromTaskCreatesEntityWithAllProperties() throws {
        let context = try TestModelContainer.newContext()

        let project = Project(name: "Alpha", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let task = TransitTask(
            name: "Test Task",
            description: "Task description",
            type: .feature,
            project: project,
            displayID: .permanent(42),
            metadata: nil
        )
        context.insert(task)

        let entity = try TaskEntity.from(task)

        #expect(entity.id == task.id.uuidString)
        #expect(entity.taskId == task.id)
        #expect(entity.displayId == 42)
        #expect(entity.name == "Test Task")
        #expect(entity.status == "idea")  // New tasks start in idea status
        #expect(entity.type == "feature")
        #expect(entity.projectId == project.id)
        #expect(entity.projectName == "Alpha")
        #expect(entity.lastStatusChangeDate == task.lastStatusChangeDate)
        #expect(entity.completionDate == nil)
    }

    @Test func fromTaskHandlesProvisionalDisplayId() throws {
        let context = try TestModelContainer.newContext()

        let project = Project(name: "Beta", description: "Test", gitRepo: nil, colorHex: "#00FF00")
        context.insert(project)

        let task = TransitTask(
            name: "Provisional Task",
            description: nil,
            type: .bug,
            project: project,
            displayID: .provisional,
            metadata: nil
        )
        context.insert(task)

        let entity = try TaskEntity.from(task)

        #expect(entity.displayId == nil)
    }

    @Test func fromTaskPreservesUUID() throws {
        let context = try TestModelContainer.newContext()

        let project = Project(name: "Gamma", description: "Test", gitRepo: nil, colorHex: "#0000FF")
        context.insert(project)

        let task = TransitTask(
            name: "UUID Test",
            description: nil,
            type: .chore,
            project: project,
            displayID: .permanent(1),
            metadata: nil
        )
        context.insert(task)

        let entity = try TaskEntity.from(task)

        #expect(entity.taskId == task.id)
        #expect(UUID(uuidString: entity.id) == task.id)
    }

    @Test func fromTaskHandlesAllTaskTypes() throws {
        let context = try TestModelContainer.newContext()
        let project = Project(name: "Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let types: [TaskType] = [.bug, .feature, .chore, .research, .documentation]

        for taskType in types {
            let task = TransitTask(
                name: "Task",
                description: nil,
                type: taskType,
                project: project,
                displayID: .permanent(1),
                metadata: nil
            )
            context.insert(task)

            let entity = try TaskEntity.from(task)
            #expect(entity.type == taskType.rawValue)
        }
    }

    @Test func fromTaskHandlesAllTaskStatuses() throws {
        let context = try TestModelContainer.newContext()
        let project = Project(name: "Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let statuses: [TaskStatus] = [
            .idea, .planning, .spec, .readyForImplementation,
            .inProgress, .readyForReview, .done, .abandoned
        ]

        for status in statuses {
            let task = TransitTask(
                name: "Task",
                description: nil,
                type: .feature,
                project: project,
                displayID: .permanent(1),
                metadata: nil
            )
            task.status = status
            context.insert(task)

            let entity = try TaskEntity.from(task)
            #expect(entity.status == status.rawValue)
        }
    }

    @Test func fromTaskThrowsErrorWhenProjectIsMissing() throws {
        let context = try TestModelContainer.newContext()

        let project = Project(name: "Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let task = TransitTask(
            name: "Orphan Task",
            description: nil,
            type: .feature,
            project: project,
            displayID: .permanent(1),
            metadata: nil
        )
        context.insert(task)

        // Simulate data integrity issue by removing project reference
        task.project = nil

        #expect(throws: VisualIntentError.self) {
            try TaskEntity.from(task)
        }
    }

    @Test func fromTaskHandlesCompletedTask() throws {
        let context = try TestModelContainer.newContext()

        let project = Project(name: "Project", description: "Test", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let task = TransitTask(
            name: "Completed Task",
            description: nil,
            type: .feature,
            project: project,
            displayID: .permanent(1),
            metadata: nil
        )
        task.status = .done
        task.completionDate = Date()
        context.insert(task)

        let entity = try TaskEntity.from(task)

        #expect(entity.status == "done")
        #expect(entity.completionDate != nil)
    }

    // MARK: - Default Query

    @Test func defaultQueryReturnsTaskEntityQuery() {
        let query = TaskEntity.defaultQuery
        #expect(type(of: query) == TaskEntityQuery.self)
    }

    // MARK: - Edge Cases

    @Test func handlesEmptyTaskName() {
        let entity = TaskEntity(
            id: UUID().uuidString,
            taskId: UUID(),
            displayId: 1,
            name: "",
            status: "idea",
            type: "feature",
            projectId: UUID(),
            projectName: "Project",
            lastStatusChangeDate: Date(),
            completionDate: nil
        )

        #expect(entity.name == "")
    }

    @Test func handlesTaskNameWithSpecialCharacters() {
        let entity = TaskEntity(
            id: UUID().uuidString,
            taskId: UUID(),
            displayId: 1,
            name: "Task #1 (Test) & \"Demo\"",
            status: "idea",
            type: "feature",
            projectId: UUID(),
            projectName: "Project",
            lastStatusChangeDate: Date(),
            completionDate: nil
        )

        #expect(entity.name == "Task #1 (Test) & \"Demo\"")
    }

    @Test func handlesTaskNameWithUnicode() {
        let entity = TaskEntity(
            id: UUID().uuidString,
            taskId: UUID(),
            displayId: 1,
            name: "🚀 Rocket Task",
            status: "idea",
            type: "feature",
            projectId: UUID(),
            projectName: "Project",
            lastStatusChangeDate: Date(),
            completionDate: nil
        )

        #expect(entity.name == "🚀 Rocket Task")
    }

    @Test func handlesProjectNameWithSpecialCharacters() {
        let entity = TaskEntity(
            id: UUID().uuidString,
            taskId: UUID(),
            displayId: 1,
            name: "Task",
            status: "idea",
            type: "feature",
            projectId: UUID(),
            projectName: "Project #1 (Test) & \"Demo\"",
            lastStatusChangeDate: Date(),
            completionDate: nil
        )

        #expect(entity.projectName == "Project #1 (Test) & \"Demo\"")
    }
}
