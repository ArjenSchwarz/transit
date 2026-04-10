import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct CreateTaskIntentTests {

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

    // MARK: - Success Cases

    @Test func validInputCreatesTaskAndReturnsSuccessJSON() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"New Task","type":"feature","description":"A description"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] is String)
        #expect(parsed["status"] as? String == "idea")
        #expect(parsed.keys.contains("displayId"))
    }

    @Test func validInputWithMetadataCreatesTask() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {
            "projectId":"\(project.id.uuidString)",
            "name":"Task With Meta",
            "type":"bug",
            "metadata":{"git.branch":"main","agent.id":"copilot"}
        }
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["status"] as? String == "idea")
        let taskIDString = try #require(parsed["taskId"] as? String)
        let taskID = try #require(UUID(uuidString: taskIDString))
        let task = try svc.task.findByID(taskID)
        #expect(task.metadata["git.branch"] == "main")
        #expect(task.metadata["agent.id"] == "copilot")
    }

    @Test func mixedTypeMetadataPreservesStringValues() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {
            "projectId":"\(project.id.uuidString)",
            "name":"Task With Mixed Meta",
            "type":"bug",
            "metadata":{"git.branch":"main","agent.id":"copilot","attempts":3}
        }
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        let taskIDString = try #require(parsed["taskId"] as? String)
        let taskID = try #require(UUID(uuidString: taskIDString))
        let task = try svc.task.findByID(taskID)
        #expect(task.metadata["git.branch"] == "main")
        #expect(task.metadata["agent.id"] == "copilot")
        #expect(task.metadata["attempts"] == nil)
    }

    @Test func stringMetadataReturnsNilForAllNonStringValues() {
        let metadata = IntentHelpers.stringMetadata(
            from: ["attempts": 3, "retries": 2] as [String: Any]
        )

        #expect(metadata == nil)
    }

    @Test func stringMetadataReturnsNilForNilInput() {
        let metadata = IntentHelpers.stringMetadata(from: nil)

        #expect(metadata == nil)
    }

    @Test func stringMetadataPreservesNativeStringDictionary() {
        let input = ["git.branch": "main", "agent.id": "copilot"]
        let metadata = IntentHelpers.stringMetadata(from: input)

        #expect(metadata == input)
    }

    @Test func stringMetadataReturnsNilForEmptyDictionary() {
        let metadata = IntentHelpers.stringMetadata(from: [String: Any]())

        #expect(metadata == nil)
    }

    // MARK: - Error Cases

    @Test func missingNameReturnsInvalidInput() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","type":"feature"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func emptyNameReturnsInvalidInput() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"","type":"feature"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func invalidTypeReturnsInvalidType() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"projectId":"\(project.id.uuidString)","name":"Task","type":"epic"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_TYPE")
    }

    @Test func malformedJSONReturnsInvalidInput() async throws {
        let svc = try makeServices()

        let result = await CreateTaskIntent.execute(
            input: "not json", taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func ambiguousProjectNameReturnsAmbiguousProject() async throws {
        let svc = try makeServices()
        makeProject(in: svc.context, name: "Transit")
        makeProject(in: svc.context, name: "transit")

        let input = """
        {"project":"Transit","name":"Task","type":"feature"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "AMBIGUOUS_PROJECT")
    }

    @Test func unknownProjectNameReturnsProjectNotFound() async throws {
        let svc = try makeServices()

        let input = """
        {"project":"NonExistent","name":"Task","type":"feature"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "PROJECT_NOT_FOUND")
    }

    // MARK: - Project Resolution

    @Test func projectIdTakesPreferenceOverProjectName() async throws {
        let svc = try makeServices()
        let targetProject = makeProject(in: svc.context, name: "Target")
        makeProject(in: svc.context, name: "Decoy")

        let input = """
        {"projectId":"\(targetProject.id.uuidString)","project":"Decoy","name":"Task","type":"feature"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["taskId"] is String)
        #expect(parsed["status"] as? String == "idea")
    }

    @Test func noProjectIdentifierReturnsInvalidInput() async throws {
        let svc = try makeServices()

        let input = """
        {"name":"Task","type":"feature"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    // MARK: - Malformed projectId [T-743]

    @Test func malformedProjectIdReturnsInvalidInput() async throws {
        // When projectId is present but not a valid UUID, should return INVALID_INPUT
        // instead of falling back to name-based lookup or no-identifier handling.
        let svc = try makeServices()
        makeProject(in: svc.context, name: "Decoy")

        let input = """
        {"name":"Task","type":"feature","projectId":"not-a-uuid","project":"Decoy"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("projectId") == true)
    }

    @Test func malformedProjectIdWithoutFallbackReturnsInvalidInput() async throws {
        // Even without a project name fallback, malformed projectId should return
        // a validation error, not a "no identifier" error.
        let svc = try makeServices()

        let input = """
        {"name":"Task","type":"feature","projectId":"not-a-uuid"}
        """

        let result = await CreateTaskIntent.execute(
            input: input, taskService: svc.task, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("projectId") == true)
    }
}
