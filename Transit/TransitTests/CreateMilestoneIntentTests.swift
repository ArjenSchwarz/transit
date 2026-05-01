import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct CreateMilestoneIntentTests {

    // MARK: - Helpers

    private struct Services {
        let milestone: MilestoneService
        let project: ProjectService
        let context: ModelContext
    }

    private func makeServices() throws -> Services {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        return Services(
            milestone: MilestoneService(modelContext: context, displayIDAllocator: allocator),
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

    @Test func validInputCreatesMilestoneAndReturnsJSON() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"v1.0","project":"\(project.name)"}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["milestoneId"] is String)
        #expect(parsed["name"] as? String == "v1.0")
        #expect(parsed["status"] as? String == "open")
        #expect(parsed.keys.contains("displayId"))
    }

    @Test func validInputWithDescriptionCreatesMilestone() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"Beta","projectId":"\(project.id.uuidString)","description":"Beta release"}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["milestoneId"] is String)
        #expect(parsed["name"] as? String == "Beta")
        #expect(parsed["status"] as? String == "open")
    }

    @Test func projectIdTakesPrecedenceOverProjectName() async throws {
        let svc = try makeServices()
        let target = makeProject(in: svc.context, name: "Target")
        makeProject(in: svc.context, name: "Decoy")

        let input = """
        {"name":"v1.0","projectId":"\(target.id.uuidString)","project":"Decoy"}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["milestoneId"] is String)
        #expect(parsed["projectId"] as? String == target.id.uuidString)
    }

    // MARK: - Error Cases

    @Test func missingNameReturnsInvalidInput() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"project":"\(project.name)"}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func emptyNameReturnsInvalidInput() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        let input = """
        {"name":"","project":"\(project.name)"}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func missingProjectReturnsInvalidInput() async throws {
        let svc = try makeServices()

        let input = """
        {"name":"v1.0"}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    @Test func unknownProjectReturnsProjectNotFound() async throws {
        let svc = try makeServices()

        let input = """
        {"name":"v1.0","project":"NonExistent"}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "PROJECT_NOT_FOUND")
    }

    @Test func duplicateNameReturnsDuplicateMilestoneName() async throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)

        // Create the first milestone
        let first = """
        {"name":"v1.0","project":"\(project.name)"}
        """
        _ = await CreateMilestoneIntent.execute(
            input: first, milestoneService: svc.milestone, projectService: svc.project
        )

        // Try to create a duplicate
        let duplicate = """
        {"name":"v1.0","project":"\(project.name)"}
        """
        let result = await CreateMilestoneIntent.execute(
            input: duplicate, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "DUPLICATE_MILESTONE_NAME")
    }

    @Test func malformedJSONReturnsInvalidInput() async throws {
        let svc = try makeServices()

        let result = await CreateMilestoneIntent.execute(
            input: "not json", milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
    }

    // MARK: - Malformed projectId [T-743]

    @Test func malformedProjectIdReturnsInvalidInput() async throws {
        // When projectId is present but not a valid UUID, should return INVALID_INPUT
        // instead of falling back to name-based lookup.
        let svc = try makeServices()
        makeProject(in: svc.context, name: "Decoy")

        let input = """
        {"name":"v1.0","projectId":"not-a-uuid","project":"Decoy"}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
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
        {"name":"v1.0","projectId":"not-a-uuid"}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("projectId") == true)
    }

    // MARK: - Non-string projectId [T-788]

    @Test func numericProjectIdRejectsWithInvalidInput() async throws {
        // projectId provided as a JSON number must not silently fall back to
        // name-based lookup. Expect INVALID_INPUT, not a successful create using "Decoy".
        let svc = try makeServices()
        makeProject(in: svc.context, name: "Decoy")

        let input = """
        {"name":"v1.0","projectId":456,"project":"Decoy"}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("projectId") == true)
    }

    @Test func numericProjectIdWithoutFallbackRejectsWithInvalidInput() async throws {
        // Without a project name fallback, a numeric projectId still must be
        // rejected as INVALID_INPUT rather than treated as missing.
        let svc = try makeServices()

        let input = """
        {"name":"v1.0","projectId":456}
        """

        let result = await CreateMilestoneIntent.execute(
            input: input, milestoneService: svc.milestone, projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("projectId") == true)
    }
}
