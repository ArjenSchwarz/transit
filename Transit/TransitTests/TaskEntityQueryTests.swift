import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskEntityQueryTests {
    private struct TestEnv {
        let context: ModelContext
        let taskService: TaskService
    }

    private func makeEnv() throws -> TestEnv {
        let schema = Schema([Project.self, TransitTask.self, Milestone.self])
        let config = ModelConfiguration(
            "TaskEntityQueryTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return TestEnv(
            context: context,
            taskService: TaskService(modelContext: context, displayIDAllocator: allocator)
        )
    }

    private func makeProject(in context: ModelContext, name: String = "Project") -> Project {
        let project = Project(name: name, description: "desc", gitRepo: nil, colorHex: "#abcabc")
        context.insert(project)
        return project
    }

    private func makeTask(
        in context: ModelContext,
        project: Project,
        name: String,
        displayID: Int,
        lastChange: Date
    ) -> TransitTask {
        let task = TransitTask(name: name, type: .feature, project: project, displayID: .permanent(displayID))
        StatusEngine.initializeNewTask(task)
        task.lastStatusChangeDate = lastChange
        context.insert(task)
        return task
    }

    @Test func entitiesForIdentifiersResolvesUUIDs() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        let first = makeTask(in: env.context, project: project, name: "First", displayID: 1, lastChange: .now)
        _ = makeTask(in: env.context, project: project, name: "Second", displayID: 2, lastChange: .now)

        let entities = TaskEntityQuery.entities(
            for: [first.id.uuidString, UUID().uuidString, "invalid"],
            taskService: env.taskService
        )

        #expect(entities.count == 1)
        #expect(entities.first?.taskId == first.id)
    }

    @Test func entitiesForIdentifiersSkipsTasksMissingProject() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        let task = makeTask(in: env.context, project: project, name: "Synced", displayID: 10, lastChange: .now)
        task.project = nil

        let entities = TaskEntityQuery.entities(for: [task.id.uuidString], taskService: env.taskService)
        #expect(entities.isEmpty)
    }

    @Test func suggestedEntitiesReturnsMostRecentTen() throws {
        let env = try makeEnv()
        let project = makeProject(in: env.context)
        let base = Date.now

        for index in 0..<12 {
            _ = makeTask(
                in: env.context,
                project: project,
                name: "Task \(index)",
                displayID: index + 1,
                lastChange: base.addingTimeInterval(TimeInterval(index))
            )
        }

        let entities = TaskEntityQuery.suggestedEntities(taskService: env.taskService)

        #expect(entities.count == 10)
        #expect(entities.first?.name == "Task 11")
        #expect(entities.last?.name == "Task 2")
    }
}
