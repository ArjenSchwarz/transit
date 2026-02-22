import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct IntentCompatibilityTests {
    private struct Services {
        let taskService: TaskService
        let projectService: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
            taskService: TaskService(modelContext: context, displayIDAllocator: allocator),
            projectService: ProjectService(modelContext: context),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String = "Compatibility") -> Project {
        let project = Project(name: name, description: "desc", gitRepo: nil, colorHex: "#3366FF")
        context.insert(project)
        return project
    }

    private func makeTask(
        in context: ModelContext,
        project: Project,
        displayId: Int = 7,
        status: TaskStatus = .idea
    ) -> TransitTask {
        let task = TransitTask(
            name: "Compatibility Task",
            type: .feature,
            project: project,
            displayID: .permanent(displayId)
        )
        StatusEngine.initializeNewTask(task)
        if status != .idea {
            StatusEngine.applyTransition(task: task, to: status)
        }
        context.insert(task)
        return task
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func parseJSONArray(_ string: String) throws -> [[String: Any]] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test func intentNamesAndModesRemainStable() {
        #expect(String(localized: QueryTasksIntent.title) == "Transit: Query Tasks")
        #expect(String(localized: CreateTaskIntent.title) == "Transit: Create Task")
        #expect(String(localized: UpdateStatusIntent.title) == "Transit: Update Status")
        #expect(String(localized: AddTaskIntent.title) == "Transit: Add Task")
        #expect(String(localized: FindTasksIntent.title) == "Transit: Find Tasks")
        #expect(String(localized: AddCommentIntent.title) == "Transit: Add Comment")
        #expect(String(localized: GenerateReportIntent.title) == "Transit: Generate Report")

        #expect(QueryTasksIntent.openAppWhenRun == true)
        #expect(CreateTaskIntent.openAppWhenRun == true)
        #expect(UpdateStatusIntent.openAppWhenRun == true)
        #expect(AddCommentIntent.openAppWhenRun == true)
        #expect(GenerateReportIntent.openAppWhenRun == false)
        #expect(AddTaskIntent.supportedModes.contains(.foreground))
        #expect(FindTasksIntent.supportedModes == [.background])

        #expect(String(localized: CreateMilestoneIntent.title) == "Transit: Create Milestone")
        #expect(String(localized: QueryMilestonesIntent.title) == "Transit: Query Milestones")
        #expect(String(localized: UpdateMilestoneIntent.title) == "Transit: Update Milestone")
        #expect(String(localized: UpdateTaskIntent.title) == "Transit: Update Task")
        #expect(CreateMilestoneIntent.openAppWhenRun == true)
        #expect(QueryMilestonesIntent.openAppWhenRun == true)
        #expect(UpdateMilestoneIntent.openAppWhenRun == true)
        #expect(UpdateTaskIntent.openAppWhenRun == true)
    }

    @Test func appShortcutsProviderIncludesAllIntents() {
        let shortcuts = TransitShortcuts.appShortcuts
        #expect(shortcuts.count == 10)
    }

    @Test func createTaskIntentJsonContractRemainsCompatible() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let result = await CreateTaskIntent.execute(
            input: "{\"projectId\":\"\(project.id.uuidString)\",\"name\":\"Contract\",\"type\":\"feature\"}",
            taskService: svc.taskService,
            projectService: svc.projectService
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] is String)
        #expect(parsed["status"] as? String == "idea")
        #expect(parsed["displayId"] is Int)
        #expect(parsed.keys.count == 3)
    }

    @Test func updateStatusIntentJsonContractRemainsCompatible() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        _ = makeTask(in: svc.context, project: project, displayId: 41)

        let result = UpdateStatusIntent.execute(
            input: "{\"displayId\":41,\"status\":\"planning\"}",
            taskService: svc.taskService
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] is String)
        #expect(parsed["displayId"] as? Int == 41)
        #expect(parsed["previousStatus"] as? String == "idea")
        #expect(parsed["status"] as? String == "planning")
        #expect(parsed.keys.count == 4)
    }

    @Test func queryTasksIntentWithoutDateFiltersRemainsCompatible() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        _ = makeTask(in: svc.context, project: project, displayId: 9, status: .inProgress)

        let result = QueryTasksIntent.execute(
            input: "{\"status\":\"in-progress\"}",
            projectService: svc.projectService,
            modelContext: svc.context
        )

        let parsed = try parseJSONArray(result)
        #expect(parsed.count == 1)
        let first = try #require(parsed.first)
        #expect(first["taskId"] is String)
        #expect(first["displayId"] as? Int == 9)
        #expect(first["name"] as? String == "Compatibility Task")
        #expect(first["status"] as? String == "in-progress")
        #expect(first["type"] as? String == "feature")
        #expect(first["projectId"] as? String == project.id.uuidString)
        #expect(first["projectName"] as? String == project.name)
        // completionDate omitted for non-completed tasks (nil = key absent)
        #expect(!first.keys.contains("completionDate"))
        #expect(first.keys.contains("lastStatusChangeDate"))
    }
}
