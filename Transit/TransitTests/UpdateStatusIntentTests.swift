import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct UpdateStatusIntentTests {
    @Test
    func validUpdateChangesStatus() async throws {
        let fixture = try await makeFixture()
        let output = UpdateStatusIntent.execute(
            input: #"{"displayId":"T-42","status":"in-progress"}"#,
            taskService: fixture.taskService
        )

        let object = try parseJSONObject(output)
        #expect(object["ok"] as? Bool == true)
        #expect(object["displayId"] as? Int == 42)
        #expect(object["status"] as? String == "in-progress")
        #expect(fixture.task.status == .inProgress)
    }

    @Test
    func unknownDisplayIDReturnsTaskNotFound() async throws {
        let fixture = try await makeFixture()
        let output = UpdateStatusIntent.execute(
            input: #"{"displayId":999,"status":"done"}"#,
            taskService: fixture.taskService
        )
        #expect(try errorCode(from: output) == "TASK_NOT_FOUND")
    }

    @Test
    func invalidStatusReturnsInvalidStatus() async throws {
        let fixture = try await makeFixture()
        let output = UpdateStatusIntent.execute(
            input: #"{"displayId":42,"status":"blocked"}"#,
            taskService: fixture.taskService
        )
        #expect(try errorCode(from: output) == "INVALID_STATUS")
    }

    @Test
    func responseFormatIncludesTaskIdentity() async throws {
        let fixture = try await makeFixture()
        let output = UpdateStatusIntent.execute(
            input: #"{"displayId":42,"status":"ready-for-review"}"#,
            taskService: fixture.taskService
        )

        let object = try parseJSONObject(output)
        #expect(object["ok"] as? Bool == true)
        #expect(object["taskId"] as? String == fixture.task.id.uuidString.lowercased())
        #expect(object["displayId"] as? Int == 42)
        #expect(object["status"] as? String == "ready-for-review")
    }
}

@MainActor
private func makeFixture() async throws -> (taskService: TaskService, task: TransitTask) {
    let container = try makeInMemoryModelContainer()
    let context = ModelContext(container)
    let projectService = ProjectService(modelContext: context)
    let project = try projectService.createProject(name: "Transit", description: "Main", color: .blue)
    let taskService = TaskService(
        modelContext: context,
        displayIDAllocator: DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 1))
    )
    let task = try await taskService.createTask(project: project, name: "Ship", type: .feature)
    task.permanentDisplayId = 42
    try context.save()
    return (taskService, task)
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
