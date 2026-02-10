import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
struct QueryTasksIntentTests {
    private struct TestServices {
        let context: ModelContext
        let taskService: TaskService
        let projectService: ProjectService
    }

    private func makeTestContext() -> TestServices {
        let schema = Schema([Project.self, TransitTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let allocator = DisplayIDAllocator(container: CKContainer(identifier: "iCloud.test"))
        let taskService = TaskService(modelContext: context, displayIDAllocator: allocator)
        let projectService = ProjectService(modelContext: context)
        return TestServices(context: context, taskService: taskService, projectService: projectService)
    }

    @Test("No filters returns all tasks")
    func noFiltersReturnsAll() async throws {
        let services = makeTestContext()
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .blue)
        services.context.insert(project)

        // Create multiple tasks
        for index in 1...3 {
            let task = TransitTask(
                name: "Task \(index)",
                description: nil,
                type: .feature,
                project: project,
                permanentDisplayId: index,
                metadata: nil
            )
            services.context.insert(task)
        }
        try services.context.save()

        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = "{}"

        let intent = QueryTasksIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = result.value

        let data = try #require(response.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(json.count == 3)
    }

    @Test("Status filter returns matching tasks")
    func statusFilterWorks() async throws {
        let services = makeTestContext()
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .blue)
        services.context.insert(project)

        let task1 = TransitTask(
            name: "Task 1",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: 1,
            metadata: nil
        )
        task1.status = .idea
        services.context.insert(task1)

        let task2 = TransitTask(
            name: "Task 2",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: 2,
            metadata: nil
        )
        task2.status = .inProgress
        services.context.insert(task2)

        try services.context.save()

        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = """
        {
            "status": "in-progress"
        }
        """

        let intent = QueryTasksIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = result.value

        let data = try #require(response.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(json.count == 1)
        #expect(json[0]["name"] as? String == "Task 2")
    }

    @Test("Project filter returns matching tasks")
    func projectFilterWorks() async throws {
        let services = makeTestContext()

        let project1 = Project(name: "Project A", description: "", gitRepo: nil, color: .blue)
        let project2 = Project(name: "Project B", description: "", gitRepo: nil, color: .red)
        services.context.insert(project1)
        services.context.insert(project2)

        let task1 = TransitTask(
            name: "Task 1",
            description: nil,
            type: .feature,
            project: project1,
            permanentDisplayId: 1,
            metadata: nil
        )
        services.context.insert(task1)

        let task2 = TransitTask(
            name: "Task 2",
            description: nil,
            type: .feature,
            project: project2,
            permanentDisplayId: 2,
            metadata: nil
        )
        services.context.insert(task2)

        try services.context.save()

        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = """
        {
            "projectId": "\(project1.id.uuidString)"
        }
        """

        let intent = QueryTasksIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = result.value

        let data = try #require(response.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(json.count == 1)
        #expect(json[0]["projectName"] as? String == "Project A")
    }

    @Test("Unknown project returns PROJECT_NOT_FOUND error")
    func unknownProjectReturnsError() async throws {
        let services = makeTestContext()
        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let randomUUID = UUID().uuidString

        let input = """
        {
            "projectId": "\(randomUUID)"
        }
        """

        let intent = QueryTasksIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = result.value

        let data = try #require(response.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["error"] as? String == "PROJECT_NOT_FOUND")
    }

    @Test("Response includes all required fields")
    func responseFieldsAreCorrect() async throws {
        let services = makeTestContext()
        let project = Project(name: "Test Project", description: "", gitRepo: nil, color: .blue)
        services.context.insert(project)

        let task = TransitTask(
            name: "Test Task",
            description: "Description",
            type: .bug,
            project: project,
            permanentDisplayId: 42,
            metadata: nil
        )
        task.status = .done
        task.completionDate = Date.now
        services.context.insert(task)
        try services.context.save()

        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = "{}"

        let intent = QueryTasksIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = result.value

        let data = try #require(response.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(json.count == 1)

        let taskJSON = json[0]
        #expect(taskJSON["taskId"] != nil)
        #expect(taskJSON["displayId"] as? Int == 42)
        #expect(taskJSON["name"] as? String == "Test Task")
        #expect(taskJSON["status"] as? String == "done")
        #expect(taskJSON["type"] as? String == "bug")
        #expect(taskJSON["projectId"] as? String == project.id.uuidString)
        #expect(taskJSON["projectName"] as? String == "Test Project")
        #expect(taskJSON["completionDate"] != nil)
        #expect(taskJSON["lastStatusChangeDate"] != nil)
    }
}
