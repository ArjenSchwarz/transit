import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct CreateTaskIntentTests {
    @Test
    func validInputCreatesTaskAndReturnsJSON() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let projectService = ProjectService(modelContext: context)
        let project = try projectService.createProject(
            name: "Transit",
            description: "Main",
            color: .blue
        )

        let taskService = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 1))
        )

        let input = """
        {
          "projectId":"\(project.id.uuidString)",
          "name":"Ship Intents",
          "description":"CLI support",
          "type":"feature",
          "metadata":{"owner":"orbit"}
        }
        """
        let output = await CreateTaskIntent.execute(
            input: input,
            taskService: taskService,
            projectService: projectService
        )
        let object = try parseJSONObject(output)

        #expect(object["ok"] as? Bool == true)
        #expect(object["status"] as? String == "idea")
        #expect(object["displayId"] as? Int == 1)
    }

    @Test
    func missingNameReturnsInvalidInput() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let projectService = ProjectService(modelContext: context)
        _ = try projectService.createProject(name: "Transit", description: "Main", color: .green)
        let taskService = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 3))
        )

        let output = await CreateTaskIntent.execute(
            input: #"{"project":"Transit","type":"feature"}"#,
            taskService: taskService,
            projectService: projectService
        )
        let errorCode = try errorCode(from: output)
        #expect(errorCode == "INVALID_INPUT")
    }

    @Test
    func invalidTypeReturnsInvalidType() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let projectService = ProjectService(modelContext: context)
        _ = try projectService.createProject(name: "Transit", description: "Main", color: .green)
        let taskService = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 5))
        )

        let output = await CreateTaskIntent.execute(
            input: #"{"project":"Transit","name":"Bad type","type":"ops"}"#,
            taskService: taskService,
            projectService: projectService
        )
        #expect(try errorCode(from: output) == "INVALID_TYPE")
    }

    @Test
    func ambiguousProjectNameReturnsAmbiguousProject() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let projectService = ProjectService(modelContext: context)
        _ = try projectService.createProject(name: "Transit", description: "One", color: .red)
        _ = try projectService.createProject(name: "transit", description: "Two", color: .orange)
        let taskService = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 7))
        )

        let output = await CreateTaskIntent.execute(
            input: #"{"project":"TRANSIT","name":"Task","type":"bug"}"#,
            taskService: taskService,
            projectService: projectService
        )
        #expect(try errorCode(from: output) == "AMBIGUOUS_PROJECT")
    }

    @Test
    func projectIDIsPreferredOverName() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let projectService = ProjectService(modelContext: context)
        let canonical = try projectService.createProject(name: "Transit", description: "Main", color: .mint)
        _ = try projectService.createProject(name: "transit", description: "Duplicate", color: .pink)

        let taskService = TaskService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 11))
        )

        let input = """
        {"projectId":"\(canonical.id.uuidString)","project":"transit","name":"Preferred project id","type":"chore"}
        """
        let output = await CreateTaskIntent.execute(
            input: input,
            taskService: taskService,
            projectService: projectService
        )

        let object = try parseJSONObject(output)
        #expect(object["ok"] as? Bool == true)

        let tasks = try context.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 1)
        #expect(tasks.first?.project?.id == canonical.id)
    }
}

private func errorCode(from json: String) throws -> String {
    let object = try parseJSONObject(json)
    let error = try #require(object["error"] as? [String: Any])
    return try #require(error["code"] as? String)
}

private func parseJSONObject(_ json: String) throws -> [String: Any] {
    let data = try #require(json.data(using: .utf8))
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}
