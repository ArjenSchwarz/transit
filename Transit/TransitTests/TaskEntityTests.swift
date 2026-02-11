import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

@Suite(.serialized)
@MainActor
struct TaskEntityTests {

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

    // MARK: - Factory Method

    @Test func fromTaskSetsIdAsUUIDString() throws {
        let context = try TestModelContainer.newContext()
        let (_, task) = makeProjectAndTask(context: context)

        let entity = try TaskEntity.from(task)
        #expect(entity.id == task.id.uuidString)
    }

    @Test func fromTaskSetsTaskId() throws {
        let context = try TestModelContainer.newContext()
        let (_, task) = makeProjectAndTask(context: context)

        let entity = try TaskEntity.from(task)
        #expect(entity.taskId == task.id)
    }

    @Test func fromTaskSetsName() throws {
        let context = try TestModelContainer.newContext()
        let (_, task) = makeProjectAndTask(context: context, taskName: "My Task")

        let entity = try TaskEntity.from(task)
        #expect(entity.name == "My Task")
    }

    @Test func fromTaskSetsStatus() throws {
        let context = try TestModelContainer.newContext()
        let (_, task) = makeProjectAndTask(context: context)

        let entity = try TaskEntity.from(task)
        #expect(entity.status == "idea")
    }

    @Test func fromTaskSetsType() throws {
        let context = try TestModelContainer.newContext()
        let (_, task) = makeProjectAndTask(context: context)

        let entity = try TaskEntity.from(task)
        #expect(entity.type == "feature")
    }

    @Test func fromTaskSetsProjectId() throws {
        let context = try TestModelContainer.newContext()
        let (project, task) = makeProjectAndTask(context: context)

        let entity = try TaskEntity.from(task)
        #expect(entity.projectId == project.id)
    }

    @Test func fromTaskSetsProjectName() throws {
        let context = try TestModelContainer.newContext()
        let (_, task) = makeProjectAndTask(context: context)

        let entity = try TaskEntity.from(task)
        #expect(entity.projectName == "TestProject")
    }

    @Test func fromTaskSetsDisplayIdWhenPermanent() throws {
        let context = try TestModelContainer.newContext()
        let (_, task) = makeProjectAndTask(context: context, displayId: 42)

        let entity = try TaskEntity.from(task)
        #expect(entity.displayId == 42)
    }

    @Test func fromTaskSetsDisplayIdNilWhenProvisional() throws {
        let context = try TestModelContainer.newContext()
        let (_, task) = makeProjectAndTask(context: context)

        let entity = try TaskEntity.from(task)
        #expect(entity.displayId == nil)
    }

    @Test func fromTaskSetsLastStatusChangeDate() throws {
        let context = try TestModelContainer.newContext()
        let (_, task) = makeProjectAndTask(context: context)

        let entity = try TaskEntity.from(task)
        #expect(entity.lastStatusChangeDate == task.lastStatusChangeDate)
    }

    @Test func fromTaskSetsCompletionDateNilForNewTask() throws {
        let context = try TestModelContainer.newContext()
        let (_, task) = makeProjectAndTask(context: context)

        let entity = try TaskEntity.from(task)
        #expect(entity.completionDate == nil)
    }

    // MARK: - Error Handling

    @Test func fromTaskThrowsWhenProjectIsNil() throws {
        let context = try TestModelContainer.newContext()
        let task = TransitTask(
            name: "Orphan Task",
            type: .bug,
            project: Project(name: "temp", description: "", gitRepo: nil, colorHex: ""),
            displayID: .provisional
        )
        context.insert(task)
        // Detach project to simulate nil
        task.project = nil
        try context.save()

        #expect(throws: VisualIntentError.self) {
            try TaskEntity.from(task)
        }
    }

    // MARK: - Display Representation

    @Test func typeDisplayRepresentationIsTask() {
        #expect(TaskEntity.typeDisplayRepresentation.name == "Task")
    }

    @Test func displayRepresentationShowsNameAndDetails() {
        let entity = TaskEntity(
            id: UUID().uuidString,
            taskId: UUID(),
            displayId: nil,
            name: "Fix Login Bug",
            status: "idea",
            type: "bug",
            projectId: UUID(),
            projectName: "Alpha",
            lastStatusChangeDate: Date(),
            completionDate: nil
        )
        #expect(entity.displayRepresentation.title == "Fix Login Bug")
    }
}
