import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskCreationResultTests {

    // MARK: - Property Storage

    @Test func holdsAllRequiredProperties() {
        let taskId = UUID()
        let projectId = UUID()
        let result = TaskCreationResult(
            id: taskId.uuidString,
            taskId: taskId,
            displayId: 42,
            status: "idea",
            projectId: projectId,
            projectName: "My Project"
        )

        #expect(result.id == taskId.uuidString)
        #expect(result.taskId == taskId)
        #expect(result.displayId == 42)
        #expect(result.status == "idea")
        #expect(result.projectId == projectId)
        #expect(result.projectName == "My Project")
    }

    @Test func nilDisplayIdIsSupported() {
        let taskId = UUID()
        let projectId = UUID()
        let result = TaskCreationResult(
            id: taskId.uuidString,
            taskId: taskId,
            displayId: nil,
            status: "idea",
            projectId: projectId,
            projectName: "Test"
        )

        #expect(result.displayId == nil)
    }

    @Test func nonNilDisplayIdIsPreserved() {
        let taskId = UUID()
        let projectId = UUID()
        let result = TaskCreationResult(
            id: taskId.uuidString,
            taskId: taskId,
            displayId: 7,
            status: "idea",
            projectId: projectId,
            projectName: "Test"
        )

        #expect(result.displayId == 7)
    }

    // MARK: - Display Representation

    @Test func displayRepresentationWithDisplayId() {
        let result = TaskCreationResult(
            id: UUID().uuidString,
            taskId: UUID(),
            displayId: 5,
            status: "idea",
            projectId: UUID(),
            projectName: "Alpha"
        )

        let rep = result.displayRepresentation
        let title = String(localized: rep.title)
        #expect(title.contains("T-5"))
    }

    @Test func displayRepresentationWithoutDisplayId() {
        let result = TaskCreationResult(
            id: UUID().uuidString,
            taskId: UUID(),
            displayId: nil,
            status: "idea",
            projectId: UUID(),
            projectName: "Alpha"
        )

        let rep = result.displayRepresentation
        let title = String(localized: rep.title)
        #expect(title.contains("Task created"))
    }

    // MARK: - Factory Method

    @Test func fromTaskAndProjectMapsFieldsCorrectly() async throws {
        let context = try TestModelContainer.newContext()
        let project = Project(name: "Test Project", description: "Desc", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let task = try await taskService.createTask(
            name: "My Task",
            description: nil,
            type: .feature,
            project: project
        )

        let result = TaskCreationResult.from(task: task, project: project)

        #expect(result.id == task.id.uuidString)
        #expect(result.taskId == task.id)
        #expect(result.status == "idea")
        #expect(result.projectId == project.id)
        #expect(result.projectName == "Test Project")
    }
}
