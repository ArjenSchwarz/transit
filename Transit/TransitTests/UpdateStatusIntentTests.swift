import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct UpdateStatusIntentTests {

    // MARK: - Helpers

    private func makeService() throws -> (TaskService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = TaskService(modelContext: context, displayIDAllocator: allocator)
        return (service, context)
    }

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test Project", description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    /// Creates a task with a known permanent display ID for testing.
    private func makeTask(
        in context: ModelContext,
        project: Project,
        displayId: Int,
        status: TaskStatus = .idea
    ) -> TransitTask {
        let task = TransitTask(name: "Test Task", type: .feature, project: project, displayID: .permanent(displayId))
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

    // MARK: - Success Cases

    @Test func validUpdateReturnsPreviousAndNewStatus() throws {
        let (taskService, context) = try makeService()
        let project = makeProject(in: context)
        makeTask(in: context, project: project, displayId: 42)

        let input = """
        {"displayId":42,"status":"planning"}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: taskService)

        let parsed = try parseJSON(result)
        #expect(parsed["displayId"] as? Int == 42)
        #expect(parsed["previousStatus"] as? String == "idea")
        #expect(parsed["status"] as? String == "planning")
    }

    @Test func updateToTerminalStatusWorks() throws {
        let (taskService, context) = try makeService()
        let project = makeProject(in: context)
        let task = makeTask(in: context, project: project, displayId: 10, status: .inProgress)

        let input = """
        {"displayId":10,"status":"done"}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: taskService)

        let parsed = try parseJSON(result)
        #expect(parsed["previousStatus"] as? String == "in-progress")
        #expect(parsed["status"] as? String == "done")
        #expect(task.completionDate != nil)
    }

    // MARK: - Error Cases

    @Test func unknownDisplayIdReturnsTaskNotFound() throws {
        let (taskService, _) = try makeService()

        let input = """
        {"displayId":999,"status":"planning"}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: taskService)

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "TASK_NOT_FOUND")
    }

    @Test func invalidStatusStringReturnsInvalidStatus() throws {
        let (taskService, context) = try makeService()
        let project = makeProject(in: context)
        makeTask(in: context, project: project, displayId: 1)

        let input = """
        {"displayId":1,"status":"flying"}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: taskService)

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_STATUS")
    }

    @Test func malformedJSONReturnsInvalidInput() throws {
        let (taskService, _) = try makeService()

        let result = UpdateStatusIntent.execute(input: "not json", taskService: taskService)

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func missingDisplayIdReturnsInvalidInput() throws {
        let (taskService, _) = try makeService()

        let input = """
        {"status":"planning"}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: taskService)

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func missingStatusReturnsInvalidInput() throws {
        let (taskService, _) = try makeService()

        let input = """
        {"displayId":1}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: taskService)

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    // MARK: - Response Format

    @Test func responseContainsAllRequiredFields() throws {
        let (taskService, context) = try makeService()
        let project = makeProject(in: context)
        makeTask(in: context, project: project, displayId: 7)

        let input = """
        {"displayId":7,"status":"spec"}
        """

        let result = UpdateStatusIntent.execute(input: input, taskService: taskService)

        let parsed = try parseJSON(result)
        #expect(parsed.keys.contains("displayId"))
        #expect(parsed.keys.contains("previousStatus"))
        #expect(parsed.keys.contains("status"))
        #expect(parsed.count == 3)
    }
}
