import Foundation
import SwiftData
import Testing
@testable import Transit

/// Integration tests: intent → service → model → dashboard filtering.
/// Verifies that tasks created/updated via App Intents appear correctly in dashboard columns.
@MainActor @Suite(.serialized)
struct IntentDashboardIntegrationTests {

    // MARK: - Helpers

    private struct Services {
        let task: TaskService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
            task: TaskService(modelContext: context, displayIDAllocator: allocator),
            project: ProjectService(modelContext: context),
            context: context
        )
    }

    @discardableResult
    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func allTasks(in context: ModelContext) throws -> [TransitTask] {
        try context.fetch(FetchDescriptor<TransitTask>())
    }

    // MARK: - Intent Creates Task Visible on Dashboard

    @Test func intentCreatedTaskAppearsInDashboardColumns() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"Intent Task","type":"feature"}
        """
        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )
        let parsed = try parseJSON(result)
        #expect(parsed["status"] as? String == "idea")

        let tasks = try allTasks(in: svc.context)
        #expect(tasks.count == 1)
        #expect(tasks[0].name == "Intent Task")

        let columns = DashboardLogic.buildFilteredColumns(allTasks: tasks, selectedProjectIDs: [])
        #expect((columns[.idea] ?? []).count == 1)
        #expect((columns[.idea] ?? [])[0].name == "Intent Task")
    }

    @Test func intentCreatedTaskVisibleWithProjectFilter() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "Alpha")
        let otherProject = makeProject(in: svc.context, name: "Beta")

        let input1 = """
        {"projectId":"\(project.id.uuidString)","name":"Alpha Task","type":"feature"}
        """
        let input2 = """
        {"projectId":"\(otherProject.id.uuidString)","name":"Beta Task","type":"bug"}
        """
        _ = await CreateTaskIntent.execute(
            input: input1, taskService: svc.task, projectService: svc.project
        )
        _ = await CreateTaskIntent.execute(
            input: input2, taskService: svc.task, projectService: svc.project
        )

        let tasks = try allTasks(in: svc.context)
        let columns = DashboardLogic.buildFilteredColumns(
            allTasks: tasks, selectedProjectIDs: [project.id]
        )
        #expect((columns[.idea] ?? []).count == 1)
        #expect((columns[.idea] ?? [])[0].name == "Alpha Task")
    }

    // MARK: - Intent Status Update Reflected in Dashboard

    @Test func intentStatusUpdateMovesTaskBetweenColumns() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let createInput = """
        {"projectId":"\(project.id.uuidString)","name":"Moving Task","type":"feature"}
        """
        let createResult = await CreateTaskIntent.execute(
            input: createInput, taskService: svc.task, projectService: svc.project
        )
        let createParsed = try parseJSON(createResult)
        let displayId = createParsed["displayId"]

        var tasks = try allTasks(in: svc.context)
        var columns = DashboardLogic.buildFilteredColumns(allTasks: tasks, selectedProjectIDs: [])
        #expect((columns[.idea] ?? []).count == 1)

        // Update status via intent
        let updateInput = """
        {"displayId":\(displayId!),"status":"in-progress"}
        """
        let updateResult = UpdateStatusIntent.execute(input: updateInput, taskService: svc.task)
        let updateParsed = try parseJSON(updateResult)
        #expect(updateParsed["previousStatus"] as? String == "idea")
        #expect(updateParsed["status"] as? String == "in-progress")

        // Verify task moved columns
        tasks = try allTasks(in: svc.context)
        columns = DashboardLogic.buildFilteredColumns(allTasks: tasks, selectedProjectIDs: [])
        #expect((columns[.idea] ?? []).count == 0)
        #expect((columns[.inProgress] ?? []).count == 1)
    }

    @Test func intentStatusUpdateToDoneAppearsInTerminalColumn() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let createInput = """
        {"projectId":"\(project.id.uuidString)","name":"Done Task","type":"chore"}
        """
        let createResult = await CreateTaskIntent.execute(
            input: createInput, taskService: svc.task, projectService: svc.project
        )
        let createParsed = try parseJSON(createResult)
        let displayId = createParsed["displayId"]

        let updateInput = """
        {"displayId":\(displayId!),"status":"done"}
        """
        _ = UpdateStatusIntent.execute(input: updateInput, taskService: svc.task)

        let tasks = try allTasks(in: svc.context)
        #expect(tasks[0].completionDate != nil)

        let columns = DashboardLogic.buildFilteredColumns(allTasks: tasks, selectedProjectIDs: [])
        #expect((columns[.doneAbandoned] ?? []).count == 1)
    }

    // MARK: - Multiple Creates Appear in Dashboard

    @Test func multipleCreatesAllAppearInDashboard() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        for index in 1...5 {
            let input = """
            {"projectId":"\(project.id.uuidString)","name":"Task \(index)","type":"feature"}
            """
            _ = await CreateTaskIntent.execute(
                input: input, taskService: svc.task, projectService: svc.project
            )
        }

        let tasks = try allTasks(in: svc.context)
        #expect(tasks.count == 5)

        let columns = DashboardLogic.buildFilteredColumns(allTasks: tasks, selectedProjectIDs: [])
        #expect((columns[.idea] ?? []).count == 5)
    }
    
    // MARK: - Visual Intent Integration Tests
    
    @Test func addTaskIntentCreatesTaskVisibleInDashboard() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context, name: "Visual Test Project")
        let projectEntity = ProjectEntity.from(project)
        
        let result = try await AddTaskIntent.execute(
            name: "Visual Intent Task",
            taskDescription: "Created via AddTaskIntent",
            type: .feature,
            project: projectEntity,
            taskService: svc.task,
            projectService: svc.project
        )
        
        #expect(result.status == "idea")
        #expect(result.projectName == "Visual Test Project")
        
        let tasks = try allTasks(in: svc.context)
        #expect(tasks.count == 1)
        #expect(tasks[0].name == "Visual Intent Task")
        #expect(tasks[0].taskDescription == "Created via AddTaskIntent")
        #expect(tasks[0].type == .feature)
        #expect(tasks[0].status == .idea)
        
        let columns = DashboardLogic.buildFilteredColumns(allTasks: tasks, selectedProjectIDs: [])
        #expect((columns[.idea] ?? []).count == 1)
        #expect((columns[.idea] ?? [])[0].name == "Visual Intent Task")
    }
    
    @Test func addTaskIntentThrowsErrorWhenNoProjectsExist() async throws {
        let svc = try makeServices()
        let dummyProjectEntity = ProjectEntity(
            id: UUID().uuidString,
            projectId: UUID(),
            name: "Nonexistent Project"
        )
        
        await #expect(throws: VisualIntentError.noProjects) {
            try await AddTaskIntent.execute(
                name: "Test Task",
                taskDescription: nil,
                type: .feature,
                project: dummyProjectEntity,
                taskService: svc.task,
                projectService: svc.project
            )
        }
    }
}
