import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
struct TaskServiceTests {
    @Test
    func createTaskInitializesIdeaAndAllocatesDisplayID() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let project = Project(name: "Transit", description: "Tracker", colorHex: "#336699")
        context.insert(project)

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 1))
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)

        let now = Date(timeIntervalSince1970: 2_000)
        let task = try await service.createTask(
            project: project,
            name: "  Build API  ",
            description: "  First cut  ",
            type: .feature,
            metadata: ["agent.owner": "orbit"],
            now: now
        )

        #expect(task.name == "Build API")
        #expect(task.taskDescription == "First cut")
        #expect(task.status == .idea)
        #expect(task.creationDate == now)
        #expect(task.lastStatusChangeDate == now)
        #expect(task.permanentDisplayId == 1)
        #expect(task.project?.id == project.id)
    }

    @Test
    func createTaskFallsBackToProvisionalWhenAllocatorFails() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let project = Project(name: "Transit", description: "Tracker", colorHex: "#336699")
        context.insert(project)

        let store = InMemoryCounterStore(initialNextDisplayID: 20)
        await store.enqueueSaveOutcomes([.failure(MockCounterError.syntheticFailure)])
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)

        let task = try await service.createTask(
            project: project,
            name: "Offline task",
            type: .bug
        )

        #expect(task.permanentDisplayId == nil)
        #expect(task.displayID == .provisional)
    }

    @Test
    func updateStatusAndLifecycleActionsApplyStatusEngineRules() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let project = Project(name: "Transit", description: "Tracker", colorHex: "#336699")
        context.insert(project)

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 3))
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        let task = try await service.createTask(project: project, name: "Workflow", type: .feature)

        let doneDate = Date(timeIntervalSince1970: 5_000)
        try service.updateStatus(task: task, to: .done, now: doneDate)
        #expect(task.status == .done)
        #expect(task.completionDate == doneDate)

        let abandonedDate = Date(timeIntervalSince1970: 5_100)
        try service.abandon(task: task, now: abandonedDate)
        #expect(task.status == .abandoned)
        #expect(task.completionDate == abandonedDate)

        let restoreDate = Date(timeIntervalSince1970: 5_200)
        try service.restore(task: task, now: restoreDate)
        #expect(task.status == .idea)
        #expect(task.completionDate == nil)
        #expect(task.lastStatusChangeDate == restoreDate)
    }

    @Test
    func findByDisplayIDReturnsTaskAndEnforcesUniqueness() throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let project = Project(name: "Transit", description: "Tracker", colorHex: "#336699")
        context.insert(project)

        let task = TransitTask(permanentDisplayId: 42, name: "Lookup", project: project)
        context.insert(task)
        try context.save()

        let service = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 100))
        )

        #expect(try service.findByDisplayID(42).id == task.id)
        #expect(throws: TaskService.Error.taskNotFound) {
            try service.findByDisplayID(900)
        }

        let duplicate = TransitTask(permanentDisplayId: 42, name: "Duplicate", project: project)
        context.insert(duplicate)
        try context.save()

        #expect(throws: TaskService.Error.duplicateDisplayID) {
            try service.findByDisplayID(42)
        }
    }

    @Test
    func createAndRestoreValidateConstraints() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let project = Project(name: "Transit", description: "Tracker", colorHex: "#336699")
        context.insert(project)

        let service = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 8))
        )

        do {
            _ = try await service.createTask(project: nil, name: "Task", type: .bug)
            Issue.record("Expected missingProject error")
        } catch let error as TaskService.Error {
            #expect(error == .missingProject)
        }

        do {
            _ = try await service.createTask(project: project, name: "   ", type: .bug)
            Issue.record("Expected invalidName error")
        } catch let error as TaskService.Error {
            #expect(error == .invalidName)
        }

        let activeTask = try await service.createTask(project: project, name: "Active", type: .feature)
        #expect(throws: TaskService.Error.restoreRequiresAbandonedTask) {
            try service.restore(task: activeTask)
        }
    }
}
