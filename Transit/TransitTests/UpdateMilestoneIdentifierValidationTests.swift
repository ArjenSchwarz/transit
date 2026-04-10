import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-753: Validates that UpdateMilestoneIntent rejects malformed milestoneId
/// and projectId identifiers instead of silently falling back to name-based lookup.
@MainActor @Suite(.serialized)
struct UpdateMilestoneIdentifierValidationTests {

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
    private func makeProject(
        in context: ModelContext, name: String = "Alpha"
    ) -> Project {
        let project = Project(
            name: name, description: "A test project",
            gitRepo: nil, colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }

    @discardableResult
    private func makeMilestone(
        in context: ModelContext,
        name: String,
        project: Project,
        displayId: Int
    ) -> Milestone {
        let milestone = Milestone(
            name: name, description: nil,
            project: project, displayID: .permanent(displayId)
        )
        context.insert(milestone)
        return milestone
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    // MARK: - Malformed milestoneId

    @Test func malformedMilestoneIdRejectsInsteadOfFallingBack() throws {
        // When milestoneId is present but not a valid UUID, the intent must
        // return INVALID_INPUT instead of falling back to name-based lookup.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"milestoneId":"not-a-uuid","name":"v1.0","project":"Alpha","status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input,
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestoneId") == true)

        // Milestone must NOT have been updated via name fallback
        let milestone = try svc.milestone.findByDisplayID(1)
        #expect(milestone.statusRawValue == "open")
    }

    // MARK: - Malformed projectId

    @Test func malformedProjectIdRejectsInsteadOfFallingBack() throws {
        // When projectId is present but not a valid UUID during name-based
        // milestone lookup, return INVALID_INPUT instead of falling back
        // to project name lookup.
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"name":"v1.0","projectId":"not-a-uuid","project":"Alpha","status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input,
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("projectId") == true)

        // Milestone must NOT have been updated via project name fallback
        let milestone = try svc.milestone.findByDisplayID(1)
        #expect(milestone.statusRawValue == "open")
    }

    // MARK: - Edge cases

    @Test func nonStringMilestoneIdRejectsWithInvalidInput() throws {
        // milestoneId provided as a number instead of a UUID string
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"milestoneId":123,"name":"v1.0","project":"Alpha","status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input,
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestoneId") == true)
    }

    @Test func emptyStringMilestoneIdRejectsWithInvalidInput() throws {
        // milestoneId as empty string is not a valid UUID
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(in: svc.context, name: "v1.0", project: project, displayId: 1)

        let input = """
        {"milestoneId":"","name":"v1.0","project":"Alpha","status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input,
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["error"] as? String == "INVALID_INPUT")
        #expect((parsed["hint"] as? String)?.contains("milestoneId") == true)
    }

    // MARK: - Valid identifiers still work

    @Test func validMilestoneIdStillWorks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        let milestone = makeMilestone(
            in: svc.context, name: "v1.0", project: project, displayId: 1
        )

        let input = """
        {"milestoneId":"\(milestone.id.uuidString)","status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input,
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["status"] as? String == "done")
    }

    @Test func validProjectIdStillWorks() throws {
        let svc = try makeServices()
        let project = makeProject(in: svc.context)
        makeMilestone(
            in: svc.context, name: "v1.0", project: project, displayId: 1
        )

        let input = """
        {"name":"v1.0","projectId":"\(project.id.uuidString)","status":"done"}
        """

        let result = UpdateMilestoneIntent.execute(
            input: input,
            milestoneService: svc.milestone,
            projectService: svc.project
        )

        let parsed = try parseJSON(result)
        #expect(parsed["status"] as? String == "done")
    }
}
