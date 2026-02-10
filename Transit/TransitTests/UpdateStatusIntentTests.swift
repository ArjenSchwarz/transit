import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
struct UpdateStatusIntentTests {
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

    @Test("Valid update changes status successfully")
    func validUpdateChangesStatus() async throws {
        let services = makeTestContext()
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .blue)
        services.context.insert(project)

        let task = TransitTask(
            name: "Test Task",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: 42,
            metadata: nil
        )
        task.status = .idea
        services.context.insert(task)
        try services.context.save()

        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = """
        {
            "task": {"displayId": 42},
            "status": "in-progress"
        }
        """

        let intent = UpdateStatusIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = result.value

        let data = try #require(response.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["displayId"] as? Int == 42)
        #expect(json["previousStatus"] as? String == "idea")
        #expect(json["status"] as? String == "in-progress")

        // Verify task status was updated
        #expect(task.status == .inProgress)
    }

    @Test("Unknown displayId returns TASK_NOT_FOUND error")
    func unknownDisplayIdReturnsError() async throws {
        let services = makeTestContext()
        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = """
        {
            "task": {"displayId": 999},
            "status": "done"
        }
        """

        let intent = UpdateStatusIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = result.value

        let data = try #require(response.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["error"] as? String == "TASK_NOT_FOUND")
        #expect((json["hint"] as? String)?.contains("999") == true)
    }

    @Test("Invalid status returns INVALID_STATUS error")
    func invalidStatusReturnsError() async throws {
        let services = makeTestContext()
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .blue)
        services.context.insert(project)

        let task = TransitTask(
            name: "Test Task",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: 42,
            metadata: nil
        )
        services.context.insert(task)
        try services.context.save()

        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = """
        {
            "task": {"displayId": 42},
            "status": "invalid-status"
        }
        """

        let intent = UpdateStatusIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = result.value

        let data = try #require(response.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["error"] as? String == "INVALID_STATUS")
        #expect((json["hint"] as? String)?.contains("invalid-status") == true)
    }

    @Test("Response format includes all required fields")
    func responseFormatIsCorrect() async throws {
        let services = makeTestContext()
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .blue)
        services.context.insert(project)

        let task = TransitTask(
            name: "Test Task",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: 10,
            metadata: nil
        )
        task.status = .planning
        services.context.insert(task)
        try services.context.save()

        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = """
        {
            "task": {"displayId": 10},
            "status": "spec"
        }
        """

        let intent = UpdateStatusIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = result.value

        let data = try #require(response.data(using: .utf8))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Verify all required fields are present
        #expect(json["displayId"] != nil)
        #expect(json["previousStatus"] != nil)
        #expect(json["status"] != nil)
        #expect(json.count == 3) // Only these three fields
    }
}
