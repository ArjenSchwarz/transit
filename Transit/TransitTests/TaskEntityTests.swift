import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskEntityTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, TransitTask.self])
        let config = ModelConfiguration(
            "TaskEntityTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func makeTask(
        in context: ModelContext,
        name: String = "Task",
        type: TaskType = .feature,
        displayID: Int = 7
    ) -> TransitTask {
        let project = Project(name: "Project", description: "desc", gitRepo: nil, colorHex: "#123123")
        context.insert(project)

        let task = TransitTask(name: name, type: type, project: project, displayID: .permanent(displayID))
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        return task
    }

    @Test func fromTaskMapsRequiredFields() throws {
        let context = try makeContext()
        let task = makeTask(in: context, name: "Map me", type: .bug, displayID: 33)

        let entity = try TaskEntity.from(task)

        #expect(entity.id == task.id.uuidString)
        #expect(entity.taskId == task.id)
        #expect(entity.displayId == 33)
        #expect(entity.name == "Map me")
        #expect(entity.status == task.statusRawValue)
        #expect(entity.type == "bug")
        #expect(entity.projectId == task.project?.id)
        #expect(entity.projectName == task.project?.name)
        #expect(entity.completionDate == nil)
    }

    @Test func fromTaskThrowsWhenProjectIsMissing() throws {
        let context = try makeContext()
        let task = makeTask(in: context)
        task.project = nil

        #expect(throws: VisualIntentError.self) {
            _ = try TaskEntity.from(task)
        }
    }
}
