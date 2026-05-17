import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskCreationResultTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, TransitTask.self, Milestone.self])
        let config = ModelConfiguration(
            "TaskCreationResultTests-\(UUID().uuidString)",
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

        let result = try TaskCreationResult.from(task)

        #expect(result.id == task.id.uuidString)
        #expect(result.taskId == task.id)
        #expect(result.displayId == 33)
        #expect(result.status == "idea")
        #expect(result.projectId == task.project?.id)
        #expect(result.projectName == task.project?.name)
        #expect(result.name == "Map me")
    }

    @Test func fromTaskThrowsWhenProjectIsMissing() throws {
        let context = try makeContext()
        let task = makeTask(in: context)
        task.project = nil

        #expect(throws: VisualIntentError.self) {
            _ = try TaskCreationResult.from(task)
        }
    }

    // T-1242 regression: the visual AddTaskIntent returns this entity, and
    // Shortcuts/result UIs render `displayRepresentation`. The title MUST be
    // the task name (not the project name) so the user sees the task that was
    // just created. The project name belongs in the subtitle as context.
    @Test func displayRepresentationUsesTaskNameAsTitle() throws {
        let context = try makeContext()
        let task = makeTask(in: context, name: "Investigate flaky test", type: .bug, displayID: 42)

        let result = try TaskCreationResult.from(task)
        let representation = result.displayRepresentation

        let title = String(localized: representation.title)
        #expect(title == "Investigate flaky test")

        // Supporting context (project / display ID / status) should still be
        // present in the subtitle so the user can verify what was created.
        let subtitle = representation.subtitle.map { String(localized: $0) } ?? ""
        #expect(subtitle.contains(task.project?.name ?? ""))
        #expect(subtitle.contains("T-42"))
        #expect(subtitle.localizedCaseInsensitiveContains("idea"))
    }
}
