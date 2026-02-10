import AppIntents
import CloudKit
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct CreateTaskIntentTests {
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

    @Test("Valid input creates task successfully")
    func validInputCreatesTask() async throws {
        let services = makeTestContext()
        let project = Project(name: "Test Project", description: "Test", gitRepo: nil, color: .blue)
        services.context.insert(project)
        try services.context.save()

        // Set up services for intent
        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = """
        {
            "name": "Test Task",
            "type": "feature",
            "projectId": "\(project.id.uuidString)",
            "description": "Test description",
            "metadata": {"key": "value"}
        }
        """

        let intent = CreateTaskIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = try #require(result.value)

        // Verify response is valid JSON
        guard let data = response.data(using: .utf8) else {
            Issue.record("Failed to convert response to data")
            return
        }
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["taskId"] != nil)
        #expect(json["displayId"] != nil)
        #expect(json["status"] as? String == "idea")

        // Verify task was created
        let tasks = try services.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 1)
        #expect(tasks[0].name == "Test Task")
        #expect(tasks[0].type == .feature)
        #expect(tasks[0].status == .idea)
    }

    @Test("Missing name returns INVALID_INPUT error")
    func missingNameReturnsError() async throws {
        let services = makeTestContext()
        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = """
        {
            "type": "feature",
            "project": "Test Project"
        }
        """

        let intent = CreateTaskIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = try #require(result.value)

        guard let data = response.data(using: .utf8) else {
            Issue.record("Failed to convert response to data")
            return
        }
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["error"] as? String == "INVALID_INPUT")
        #expect((json["hint"] as? String)?.contains("name") == true)
    }

    @Test("Invalid type returns INVALID_TYPE error")
    func invalidTypeReturnsError() async throws {
        let services = makeTestContext()
        let project = Project(name: "Test", description: "", gitRepo: nil, color: .blue)
        services.context.insert(project)
        try services.context.save()

        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = """
        {
            "name": "Test Task",
            "type": "invalid-type",
            "projectId": "\(project.id.uuidString)"
        }
        """

        let intent = CreateTaskIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = try #require(result.value)

        guard let data = response.data(using: .utf8) else {
            Issue.record("Failed to convert response to data")
            return
        }
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["error"] as? String == "INVALID_TYPE")
        #expect((json["hint"] as? String)?.contains("invalid-type") == true)
    }

    @Test("Ambiguous project name returns AMBIGUOUS_PROJECT error")
    func ambiguousProjectReturnsError() async throws {
        let services = makeTestContext()

        // Create two projects with the same name
        let project1 = Project(name: "Duplicate", description: "First", gitRepo: nil, color: .blue)
        let project2 = Project(name: "Duplicate", description: "Second", gitRepo: nil, color: .red)
        services.context.insert(project1)
        services.context.insert(project2)
        try services.context.save()

        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = """
        {
            "name": "Test Task",
            "type": "feature",
            "project": "Duplicate"
        }
        """

        let intent = CreateTaskIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = try #require(result.value)

        guard let data = response.data(using: .utf8) else {
            Issue.record("Failed to convert response to data")
            return
        }
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["error"] as? String == "AMBIGUOUS_PROJECT")
        #expect((json["hint"] as? String)?.contains("2 projects") == true)
    }

    @Test("ProjectId takes precedence over project name")
    func projectIdTakesPrecedence() async throws {
        let services = makeTestContext()

        let project1 = Project(name: "Project A", description: "First", gitRepo: nil, color: .blue)
        let project2 = Project(name: "Project B", description: "Second", gitRepo: nil, color: .red)
        services.context.insert(project1)
        services.context.insert(project2)
        try services.context.save()

        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        // Provide both projectId (for project1) and project name (for project2)
        let input = """
        {
            "name": "Test Task",
            "type": "feature",
            "projectId": "\(project1.id.uuidString)",
            "project": "Project B"
        }
        """

        let intent = CreateTaskIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = try #require(result.value)

        // Should succeed and use project1 (projectId takes precedence)
        guard let data = response.data(using: .utf8) else {
            Issue.record("Failed to convert response to data")
            return
        }
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["error"] == nil)

        // Verify task was created with project1
        let tasks = try services.context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 1)
        #expect(tasks[0].project?.id == project1.id)
    }

    @Test("Unknown project returns PROJECT_NOT_FOUND error")
    func unknownProjectReturnsError() async throws {
        let services = makeTestContext()
        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = """
        {
            "name": "Test Task",
            "type": "feature",
            "project": "Nonexistent Project"
        }
        """

        let intent = CreateTaskIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = try #require(result.value)

        guard let data = response.data(using: .utf8) else {
            Issue.record("Failed to convert response to data")
            return
        }
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["error"] as? String == "PROJECT_NOT_FOUND")
    }

    @Test("Malformed JSON returns INVALID_INPUT error")
    func malformedJSONReturnsError() async throws {
        let services = makeTestContext()
        TransitServices.shared.services = (taskService: services.taskService, projectService: services.projectService)

        let input = "{ invalid json }"

        let intent = CreateTaskIntent()
        intent.input = input

        let result = try await intent.perform()
        let response = try #require(result.value)

        guard let data = response.data(using: .utf8) else {
            Issue.record("Failed to convert response to data")
            return
        }
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["error"] as? String == "INVALID_INPUT")
    }
}
